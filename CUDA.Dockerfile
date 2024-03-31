# Stage 0: Intel MKL
ARG CUDA_VERSION=12.2.2
FROM intel/oneapi-basekit AS mkl-env

# Stage 1: Build dependencies
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04 AS build-env

# Install as root
USER root

# 필수 패키지 설치, OpenBLAS 설치 추가
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
    --no-install-recommends \
    cmake \
    git \
    linux-headers-generic \
    python3 python3-dev python3-pip python-is-python3 \
    wget \
    tar \
    openssh-server \
    libopenblas-dev && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Python 빌드 의존성, torch 관련 패키지 및 VESSL CLI 설치
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir pybind11 scikit-build protobuf mypy && \
    pip install torch torchvision torchmetrics && \
    pip install vessl

# 사용자 추가 및 권한 설정
ARG USERNAME=coder
ARG USERID=1000
ARG GROUPID=1000
RUN groupadd -g ${GROUPID} ${USERNAME} && \
    useradd -m ${USERNAME} --uid ${USERID} --gid ${GROUPID} --shell=/bin/bash

# MKL 라이브러리 복사
COPY --from=mkl-env /opt/intel/oneapi/mkl /opt/intel/oneapi/mkl

# aihwkit 소스 복사 및 빌드
COPY . /aihwkit
RUN chown -R ${USERNAME}:${USERNAME} /aihwkit && \
    pip install --no-cache-dir /aihwkit

# JupyterLab, Anaconda 설치 및 설정
RUN wget https://repo.anaconda.com/archive/Anaconda3-2021.05-Linux-x86_64.sh -O /tmp/anaconda.sh && \
    /bin/bash /tmp/anaconda.sh -b -p /opt/conda && \
    rm /tmp/anaconda.sh && \
    ln -s /opt/conda/bin/jupyter /usr/local/bin/jupyter && \
    /opt/conda/bin/conda init bash && \
    /opt/conda/bin/conda create -y -n aihwkit python=3.9 && \
    /opt/conda/bin/conda run -n aihwkit pip install pandas matplotlib openpyxl 'wandb>=0.12.10'

# sshd 설정 (예시, 실제 설정은 환경에 따라 다를 수 있음)
RUN mkdir /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 환경 변수 설정
ENV PATH /opt/conda/bin:$PATH
ENV LD_LIBRARY_PATH /opt/intel/oneapi/mkl/latest/lib/intel64:${LD_LIBRARY_PATH}

# 포트 노출
EXPOSE 22 8888

# 사용자 전환 및 작업 디렉토리 설정
USER ${USERNAME}
WORKDIR /aihwkit

# JupyterLab 및 SSH 서버 시작 스크립트
CMD ["/bin/bash", "-c", "/usr/sbin/sshd && jupyter lab --ip=0.0.0.0 --no-browser --allow-root"]
