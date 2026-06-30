# Build context is app/ (see Project 2 buildspec: `docker build ... app/`).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# The pipeline passes the git SHA; /version echoes it to prove which build is live.
ARG VERSION=dev
ENV VERSION=$VERSION

EXPOSE 8080

# App SG only accepts 8080 from the ALB; container + taskdef + appspec all agree on it.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
