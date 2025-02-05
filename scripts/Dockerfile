FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy script into the container
COPY check-actions.sh /check-actions.sh
RUN chmod +x /check-actions.sh
ENV LANG=C.UTF-8
CMD ["/check-actions.sh"]
