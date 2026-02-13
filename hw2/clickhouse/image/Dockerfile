FROM clickhouse/clickhouse-server:24.3

COPY table.sql /docker-init/table.sql
COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

ENTRYPOINT ["/usr/local/bin/run.sh"]
