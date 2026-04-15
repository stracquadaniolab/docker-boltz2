# =============================================================================
# Boltz-2 Docker Image with NVIDIA GPU Support
# =============================================================================
# Base: NVIDIA CUDA 12.4 + cuDNN 9 on Ubuntu 22.04
# Python: 3.11 (required: >=3.10, <3.13)
# Boltz:  latest from PyPI (boltz[cuda])
#
# Build:
#   docker build -t boltz2:cuda124 .
#
# Run (GPU):
#   docker run --gpus all --rm \
#     -v $(pwd)/data:/data \
#     -v $(pwd)/cache:/root/.boltz \
#     boltz2:cuda124 boltz predict /data/input.yaml --use_msa_server --output_format mmcif
# =============================================================================

FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# --------------------------------------------------------------------------- #
# Build arguments (override at build time if needed)
# --------------------------------------------------------------------------- #
ARG PYTHON_VERSION=3.11
# pin e.g. "==2.2.1" or leave empty for latest
ARG BOLTZ_VERSION=""          
ARG TORCH_CUDA_INDEX="https://download.pytorch.org/whl/cu124"

# --------------------------------------------------------------------------- #
# Environment
# --------------------------------------------------------------------------- #
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Boltz model weights / CCD cache directory
    BOLTZ_CACHE=/root/.boltz \
    # Torch settings
    TORCH_HOME=/root/.cache/torch \
    # cuEquivariance acceleration (NVIDIA kernels, optional)
    CUEQ_DISABLE=0

# --------------------------------------------------------------------------- #
# System packages
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libgomp1 \
        libglib2.0-0 \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        python${PYTHON_VERSION}-distutils \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python / pip
RUN update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python

# --------------------------------------------------------------------------- #
# PyTorch — install CUDA-enabled wheel BEFORE boltz so the cuda extra
# doesn't pull in a CPU-only torch from PyPI.
# --------------------------------------------------------------------------- #
RUN pip install --upgrade pip setuptools wheel && \
    pip install \
        torch \
        torchvision \
        torchaudio \
        --index-url ${TORCH_CUDA_INDEX}

# --------------------------------------------------------------------------- #
# Boltz-2 (with CUDA extras for cuEquivariance kernels)
# --------------------------------------------------------------------------- #
RUN pip install "boltz[cuda]${BOLTZ_VERSION}"

# --------------------------------------------------------------------------- #
# Optional: NVIDIA cuEquivariance Python bindings (accelerates equivariant ops)
# Safe to skip if not available for your arch — Boltz falls back gracefully.
# --------------------------------------------------------------------------- #
RUN pip install cuequivariance-torch cuequivariance-ops-torch-cu12 \
        --extra-index-url https://pypi.nvidia.com || \
    echo "WARNING: cuEquivariance packages unavailable for this platform, continuing without."

# --------------------------------------------------------------------------- #
# Create directories
# --------------------------------------------------------------------------- #
RUN mkdir -p ${BOLTZ_CACHE} /data /workspace

# --------------------------------------------------------------------------- #
# Smoke-test: verify CUDA is visible at import time
# --------------------------------------------------------------------------- #
# RUN python -c " \
# import torch; \
# print('PyTorch version :', torch.__version__); \
# print('CUDA available  :', torch.cuda.is_available()); \
# print('CUDA built      :', torch.version.cuda); \
# import boltz; \
# print('Boltz version   :', boltz.__version__); \
# "

# --------------------------------------------------------------------------- #
# Labels
# --------------------------------------------------------------------------- #
LABEL org.opencontainers.image.title="boltz2-gpu" \
      org.opencontainers.image.description="Boltz-2 biomolecular interaction model with NVIDIA GPU support" \
      org.opencontainers.image.source="https://github.com/jwohlwend/boltz" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /workspace
VOLUME ["/data", "/root/.boltz"]

ENTRYPOINT ["boltz"]
CMD ["--help"]