ARG JAVA_VERSION=25
FROM eclipse-temurin:${JAVA_VERSION}-jre

RUN apt update && apt install -y jq curl && apt -y clean

WORKDIR /server

COPY server-manager.sh /opt/server-manager.sh
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/server-manager.sh /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
