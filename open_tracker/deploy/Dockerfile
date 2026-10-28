FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 TRACKER_CONTAINER=1
WORKDIR /app
COPY open_tracker/requirements-shared.txt /app/open_tracker/requirements-shared.txt
RUN python -m pip install --no-cache-dir -r /app/open_tracker/requirements-shared.txt \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin tracker \
    && mkdir /data && chown tracker:tracker /data

# Explicit source list: private workspaces and local files cannot enter the image.
COPY LICENSE /app/LICENSE
COPY open_tracker/tracker.py open_tracker/server.py open_tracker/notifications.py open_tracker/manage.py open_tracker/index.html /app/open_tracker/
COPY open_tracker/examples/status.csv /app/open_tracker/examples/status.csv
COPY open_tracker/deploy/healthcheck.py /app/open_tracker/deploy/healthcheck.py
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "/app/open_tracker/deploy/healthcheck.py"]
ENTRYPOINT ["python", "/app/open_tracker/manage.py", "--workspace", "/data"]
CMD ["start", "--host", "0.0.0.0"]
