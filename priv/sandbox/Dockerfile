FROM ubuntu:26.04

# Отключаем интерактивные диалоги apt
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем базовые утилиты, которые часто нужны агентам
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    wget \
    git \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    jq \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Создаем рабочую директорию, куда будем монтировать workspace с хоста
WORKDIR /workspace

# По умолчанию запускаем bash
CMD ["/bin/bash"]
