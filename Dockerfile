FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml README.md LICENSE requirements.txt ./
COPY vio ./vio
COPY configs ./configs
COPY skills ./skills
RUN pip install --no-cache-dir -e .
ENV VIO_HOST=0.0.0.0 VIO_PORT=8787 VIO_DATA_DIR=/data
EXPOSE 8787
VOLUME ["/data"]
CMD ["vio", "serve"]
