FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY server/requirements.lock /app/requirements.lock
RUN pip install --no-cache-dir -r requirements.lock && useradd -u 10001 -m appuser
COPY server /app
COPY web /web
RUN mkdir -p /data/uploads && chown -R appuser:appuser /data /app
USER appuser
ENV WEB_DIR=/web UPLOAD_DIR=/data/uploads
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --no-access-log --proxy-headers --forwarded-allow-ips='*'"]
