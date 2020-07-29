FROM ubuntu:20.04

LABEL maintainer "PenUltima Online <polteam@polserver.com>"

RUN apt-get update && \
    apt-get install -y curl unzip libatomic1 mysql-common && \
    curl -o /tmp/libmysqlclient20_5.7.26-1+b1_amd64.deb http://ftp.br.debian.org/debian/pool/main/m/mysql-5.7/libmysqlclient20_5.7.26-1+b1_amd64.deb && \
    dpkg -i /tmp/libmysqlclient20_5.7.26-1+b1_amd64.deb

COPY app.sh /app/app.sh

EXPOSE 5003

ENTRYPOINT ["/app/app.sh"]
