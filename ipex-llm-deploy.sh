#!/bin/sh

set -x
set -e

echo "Install oneapi"

ollama_serve_f="run-ollama-serve.sh"
run_ref_f="run-deepseek.sh"
oneapi_gpg_f="/usr/share/keyrings/oneapi-archive-keyring.gpg"

if [ -f $oneapi_gpg_f ]; then
        echo "$oneapi_gpg_f exist, skipped!"
else
        wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
fi

echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | sudo tee /etc/apt/sources.list.d/oneAPI.list

sudo apt update

sudo apt install -y intel-oneapi-common-vars=2024.0.0-49406 \
  intel-oneapi-common-oneapi-vars=2024.0.0-49406 \
  intel-oneapi-diagnostics-utility=2024.0.0-49093 \
  intel-oneapi-compiler-dpcpp-cpp=2024.0.2-49895 \
  intel-oneapi-dpcpp-ct=2024.0.0-49381 \
  intel-oneapi-mkl=2024.0.0-49656 \
  intel-oneapi-mkl-devel=2024.0.0-49656 \
  intel-oneapi-mpi=2021.11.0-49493 \
  intel-oneapi-mpi-devel=2021.11.0-49493 \
  intel-oneapi-dal=2024.0.1-25 \
  intel-oneapi-dal-devel=2024.0.1-25 \
  intel-oneapi-ippcp=2021.9.1-5 \
  intel-oneapi-ippcp-devel=2021.9.1-5 \
  intel-oneapi-ipp=2021.10.1-13 \
  intel-oneapi-ipp-devel=2021.10.1-13 \
  intel-oneapi-tlt=2024.0.0-352 \
  intel-oneapi-ccl=2021.11.2-5 \
  intel-oneapi-ccl-devel=2021.11.2-5 \
  intel-oneapi-dnnl-devel=2024.0.0-49521 \
  intel-oneapi-dnnl=2024.0.0-49521 \
  intel-oneapi-tcm-1.0=1.0.0-435

# TODO: where can we know the oneapi version mapping for ipex-llm's version/tag/release??
echo "FIXME: for latest ipex-llm(date 2025.2.8), upgrade oneapi to 2025"
sudo apt install -y intel-oneapi-dnnl-2025.0 intel-oneapi-mkl-sycl-2025.0 intel-oneapi-dpcpp-cpp-2025.0

echo "Setup python environment"
if [ -f Miniforge3-Linux-x86_64.sh ]; then
        echo "Miniforge already exists, skipped"
else
        wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
        echo "Miniforge2 downloaded, now installing"
        echo "====================================="
        echo "lease type yes to accept the licences and agree to init by default!!"
        bash Miniforge3-Linux-x86_64.sh
fi
source ~/.bashrc

echo "Create python llm env and install ipex-llm"
# TODO: how to know whether this llm-cpp env already exists?
#conda create -n llm-cpp python=3.11
eval "$(conda shell.bash hook)"
conda activate llm-cpp
pip install --pre --upgrade ipex-llm[cpp]

if [ ! -d "./llama-cpp" ]; then
        mkdir llama-cpp
fi
cd llama-cpp
init-ollama

if [ -f $ollama_serve_f ]; then
        echo "$ollama_serve_f exists, skipped!"
else
        tee $ollama_serve_f <<EOF
export OLLAMA_NUM_GPU=999
export no_proxy=localhost,127.0.0.1
export ZES_ENABLE_SYSMAN=1

source /opt/intel/oneapi/setvars.sh
export SYCL_CACHE_PERSISTENT=1
# [optional] under most circumstances, the following environment variable may improve performance, but sometimes this may also cause performance degradation
export SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1
# [optional] if you want to run on single GPU, use below command to limit GPU may improve performance
export ONEAPI_DEVICE_SELECTOR=level_zero:0

./ollama serve
EOF
        chmod +x $ollama_serve_f
fi

echo "ipex-llm and ollama deployed done, you can run $ollama_serve_f to start ollama server!"


if [ -f $run_ref_f ]; then
        echo "$run_ref_f exists, skipped!"
else
        tee $run_ref_f <<EOF
source /opt/intel/oneapi/setvars.sh
export no_proxy=localhost,127.0.0.1
./ollama run deepseek-r1:8b
EOF
        chmod +x $run_ref_f
fi

echo "$run_ref_f as the reference command to pull and run the model, enjoy!"
