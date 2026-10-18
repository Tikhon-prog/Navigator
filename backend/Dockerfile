FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app

COPY backend/requirements.txt /app/backend/requirements.txt
COPY backend/requirements-firebase.txt /app/backend/requirements-firebase.txt
RUN python -m pip install --no-cache-dir -r /app/backend/requirements.txt
ARG ENABLE_FIREBASE=false
RUN if [ "$ENABLE_FIREBASE" = "true" ]; then python -m pip install --no-cache-dir -r /app/backend/requirements-firebase.txt; fi

COPY backend /app/backend
# Run as a non-root service user. The Compose database volume is mounted at /data.
RUN addgroup --system app && adduser --system --ingroup app app \
    && mkdir -p /data \
    && chown -R app:app /app/backend /data
USER app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v2/health', timeout=3).read()" || exit 1
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
