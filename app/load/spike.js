// Skybound Arena — k6 spike load test.
//
// Purpose: drive REAL traffic at the dev ALB so the ECS service crosses its 60% CPU
// scale-out target and the autoscaler adds tasks — then subsides so it scales back in.
// This is also the first thing to exercise the Slice-2 alarm stack on real metrics
// instead of `set-alarm-state`.
//
// This is a LOCAL tool. It is not deployed and touches no infrastructure. It hits the
// already-public dev ALB on port 80.
//
//   BASE_URL=http://<alb-dns> k6 run spike.js
//
// Get the URL from Terraform: `terraform output -raw alb_dns_name` in environments/dev.
//
// Caveat — matchmaking is in-memory PER TASK. With more than one running task, the two
// queue calls in an iteration can land on different tasks and both stay QUEUED (no
// match forms). That is expected and fine: the goal is REQUEST VOLUME to move CPU, not
// guaranteed match formation. Matches that do form still settle correctly (match state
// lives in DynamoDB). Do not add checks that assume a match always forms.
//
// Guardrail — keep the spike below health-check failure. If tasks saturate hard enough
// to fail /healthz, the Slice-2 `unhealthy_hosts` alarm trips and the heal Lambda
// forces a full blue/green redeploy that fights the autoscaler (there is no heal
// cooldown yet). The default profile below is sized to cross 60% CPU, not to knock
// tasks over. See README.md before turning the volume up.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || '').replace(/\/$/, '');
if (!BASE_URL) {
  throw new Error('Set BASE_URL, e.g. BASE_URL=http://<alb-dns> k6 run spike.js');
}

const matchesFormed = new Counter('matches_formed');

export const options = {
  // A spike: warm up, ramp hard, sustain to let the autoscaler react, then drain so
  // scale-in is observable. Tune the peak VUs to your task size (256 CPU units in dev).
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '1m', target: 20 },  // warm up, establish a CPU baseline
        { duration: '2m', target: 80 },  // ramp hard toward the 60% scale-out target
        { duration: '4m', target: 80 },  // sustain — give the autoscaler time to add tasks
        { duration: '2m', target: 0 },   // drain — watch tasks scale back in
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // Fail the run if the service is actually erroring — a real regression, not load.
    http_req_failed: ['rate<0.05'],
  },
};

function post(path, body) {
  return http.post(`${BASE_URL}${path}`, JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export default function () {
  // Unique usernames per VU/iteration so player creation never collides.
  const suffix = `${__VU}-${__ITER}-${Math.floor(Math.random() * 1e6)}`;

  // 1. Create a pair of players.
  const a = post('/players', { username: `load_a_${suffix}` });
  const b = post('/players', { username: `load_b_${suffix}` });
  check(a, { 'player A created': (r) => r.status === 201 });
  check(b, { 'player B created': (r) => r.status === 201 });
  if (a.status !== 201 || b.status !== 201) {
    sleep(1);
    return;
  }
  const playerA = a.json('player_id');
  const playerB = b.json('player_id');

  // 2. Queue both. A match forms only if both land on the same task (see header).
  post('/matchmaking/queue', { player_id: playerA });
  const q2 = post('/matchmaking/queue', { player_id: playerB });
  check(q2, { 'queue accepted': (r) => r.status === 200 });

  // 3. If a match formed, report a result (winner = player A).
  if (q2.status === 200 && q2.json('status') === 'MATCHED') {
    const matchId = q2.json('match_id');
    matchesFormed.add(1);
    const res = post(`/matches/${matchId}/result`, { winner: playerA });
    check(res, { 'result recorded': (r) => r.status === 200 });
  }

  // 4. Read paths — leaderboard and health — round out a realistic mix.
  check(http.get(`${BASE_URL}/leaderboard?limit=10`), { 'leaderboard ok': (r) => r.status === 200 });
  check(http.get(`${BASE_URL}/healthz`), { 'healthz ok': (r) => r.status === 200 });

  sleep(1);
}
