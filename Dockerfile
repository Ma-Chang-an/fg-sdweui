# syntax = docker/dockerfile:experimental

# # WebUI 基础镜像
# # 包含 WebUI、相关依赖、插件、Lora、VAE

############################# 
#     clone repositories    #
#############################
FROM alpine/git:2.36.2 as repositories

COPY clone.sh /clone.sh

# RUN . /clone.sh taming-transformers https://github.com/CompVis/taming-transformers.git 3ba01b241669f5ade541ce990f7650a3b8f65318 \
#     && rm -rf data assets **/*.ipynb

RUN . /clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git cf1d67a6fd5ea1aa600c4df58e5b47da45f6bdbf \
    && rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

RUN . /clone.sh generative-models https://github.com/Stability-AI/generative-models.git 5c10deee76adad0032b412294130090932317a87 \
    && rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

RUN . /clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af \
    && rm -rf assets inputs

RUN . /clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9
RUN . /clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git c9fe758757e022f05ca5a53fa8fac28889e4f1cf
RUN . /clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2486589f24165c8e3b303f84e9dbbea318df83e8

RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git /stable-diffusion-webui && \
    cd /stable-diffusion-webui && \
    git reset --hard v1.6.0

RUN git lfs install

RUN GIT_LFS_SKIP_SMUDGE=1 git clone https://huggingface.co/openai/clip-vit-large-patch14 /clip-vit-large-patch14

############################# 
#     download xformers     #
#############################

FROM alpine:3.17 as xformers

RUN apk add --no-cache aria2
RUN aria2c -x 5 --dir / --out wheel.whl 'https://github.com/AbdBarho/stable-diffusion-webui-docker/releases/download/5.0.3/xformers-0.0.20.dev528-cp310-cp310-manylinux2014_x86_64-pytorch2.whl'

    
# ############################# 
# #     extension models     d#
# #############################

FROM python:3.10.9-slim as extensions

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install transformers[sentencepiece] sentencepiece && \
    pip install torch==2.0.1 torchvision==0.15.2 --index-url https://download.pytorch.org/whl/cu118

COPY ./init /init
RUN mkdir -p /sd-prompt-translator && python /init/sd-prompt-translator.py /sd-prompt-translator
RUN mkdir -p /bert-base-uncased-cache && python /init/bert-base-uncased.py /bert-base-uncased-cache
RUN mkdir -p /models--Bingsu--adetailer && python /init/bingsu-adetailer.py /models--Bingsu--adetailer

# ############################# 
# #           models          #
# #############################
FROM alpine:3.17 as models

RUN apk add --no-cache aria2 unzip

RUN aria2c -x 8 --dir "/" --out "codeformer-v0.1.0.pth" "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth"  
RUN aria2c -x 8 --dir "/" --out "detection_Resnet50_Final.pth" "https://github.com/xinntao/facexlib/releases/download/v0.1.0/detection_Resnet50_Final.pth" 
RUN aria2c -x 8 --dir "/" --out "parsing_parsenet.pth" "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/parsing_parsenet.pth" 
RUN aria2c -x 8 --dir "/" --out "model_base_caption_capfilt_large.pth" "https://storage.googleapis.com/sfr-vision-language-research/BLIP/models/model_base_caption_capfilt_large.pth" 
RUN aria2c -x 8 --dir "/" --out "model-resnet_custom_v3.pt" "https://github.com/AUTOMATIC1111/TorchDeepDanbooru/releases/download/v1/model-resnet_custom_v3.pt" 
RUN aria2c -x 8 --dir "/" --out "inswapper_128.onnx" "https://drive.google.com/u/0/uc?id=1krOLgjW2tAPaqV-Bw4YALz0xT5zlb5HF&export=download" 
RUN aria2c -x 8 --dir "/" --out "detector.onnx" "https://huggingface.co/s0md3v/nudity-checker/resolve/main/detector.onnx" 
RUN aria2c -x 8 --dir "/" --out "control_v11p_sd15_scribble.pth" "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_scribble.pth"
RUN aria2c -x 8 --dir "/" --out "control_v11p_sd15_scribble.yaml" "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_scribble.yaml"
RUN aria2c -x 8 --dir "/" --out "control_v1p_sd15_illumination.safetensors" "https://huggingface.co/ioclab/ioc-controlnet/resolve/main/models/control_v1p_sd15_illumination.safetensors"
RUN aria2c -x 8 --dir "/" --out "buffalo_l.zip" "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip"
RUN unzip /buffalo_l.zip -d /buffalo_l
  
# ############################# 
# #           dist            #
# #############################


FROM nvidia/cuda:11.8.0-base-ubuntu22.04 as sd_base

ENV DEBIAN_FRONTEND=noninteractive PIP_PREFER_BINARY=1
ENV GROUP_ID=1003
ENV USER_ID=1003
ENV GROUP_NAME=paas
ENV USER_NAME=paas
ENV HOME=/home/paas

RUN groupadd -g ${GROUP_ID} ${GROUP_NAME} && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} ${USER_NAME}

RUN --mount=type=cache,target=/var/cache/apt \
    apt update && \
    apt install -y \
        wget git fonts-dejavu-core rsync git jq moreutils aria2 \
        ffmpeg libglfw3-dev libgles2-mesa-dev pkg-config libcairo2 libcairo2-dev \
        gcc g++ procps unzip curl python3 python3-pip

RUN ln -sfn /usr/bin/python3 /usr/bin/python

ENV ROOT=${HOME}/stable-diffusion-webui

COPY --from=repositories --chown=${USER_NAME}:${GROUP_NAME} /stable-diffusion-webui ${ROOT}
COPY --from=repositories --chown=${USER_NAME}:${GROUP_NAME} /repositories/ ${ROOT}/repositories/
COPY --from=repositories --chown=${USER_NAME}:${GROUP_NAME} /clip-vit-large-patch14 ${HOME}/openai/clip-vit-large-patch14

RUN sed -i ${ROOT}/repositories/stable-diffusion-stability-ai/ldm/modules/encoders/modules.py -e 's@openai/clip-vit-large-patch14@/home/paas/openai/clip-vit-large-patch14@'

RUN --mount=type=cache,target=/root/.cache/pip \
    cd ${ROOT} && \
    pip install -r requirements_versions.txt && \
    find ${ROOT}/repositories -name requirements.txt | xargs -I {} pip install -r {} || echo "failed" && \
    pip install rich==13.4.2 numexpr matplotlib pandas av pims imageio_ffmpeg gdown mediapipe==0.10.2 \
        ultralytics==8.0.145 py-cpuinfo protobuf==3.20 rembg==2.0.38 \
        deepdanbooru onnxruntime-gpu jsonschema opencv_contrib_python opencv_python opencv_python_headless packaging Pillow tqdm \
        chardet PyExecJS lxml pathos cryptography openai aliyun-python-sdk-core aliyun-python-sdk-alimt send2trash \
        insightface==0.7.3 tensorflow ifnude && \
    pip install xformers==0.0.20 taming-transformers-rom1504 && \
    pip install torch==2.0.1 torchvision==0.15.2 --index-url https://download.pytorch.org/whl/cu118

# ==========================

FROM sd_base as base

ENV SD_BUILTIN=/built-in

COPY --chown=${USER_NAME}:${GROUP_NAME} ./sd-resource/config.json ${ROOT}/config.json
COPY --chown=${USER_NAME}:${GROUP_NAME} ./sd-resource/ui-config.json ${ROOT}/ui-config.json
COPY --chown=${USER_NAME}:${GROUP_NAME} ./sd-resource/extensions ${ROOT}/extensions
COPY --chown=${USER_NAME}:${GROUP_NAME} ./sd-resource/localizations ${ROOT}/localizations
COPY --chown=${USER_NAME}:${GROUP_NAME} ./sd-resource ${SD_BUILTIN}
#COPY --chown=${USER_NAME}:${GROUP_NAME} ./mount.sh ${HOME}/mount.sh

# 中文提示词翻译 299M
COPY --from=extensions --chown=${USER_NAME}:${GROUP_NAME} /sd-prompt-translator ${ROOT}/extensions/sd-prompt-translator/scripts/models
COPY --from=extensions --chown=${USER_NAME}:${GROUP_NAME} /bert-base-uncased-cache/*  ${HOME}/root/.cache/huggingface/hub/

# 面部修复 + 高分辨率修复 359M + 104M + 81.4M
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /codeformer-v0.1.0.pth ${ROOT}/models/Codeformer/codeformer-v0.1.0.pth
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /detection_Resnet50_Final.pth ${ROOT}/repositories/CodeFormer/weights/facelib/detection_Resnet50_Final.pth
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /parsing_parsenet.pth ${ROOT}/repositories/CodeFormer/weights/facelib/parsing_parsenet.pth

COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /codeformer-v0.1.0.pth ${SD_BUILTIN}/models/Codeformer/codeformer-v0.1.0.pth
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /detection_Resnet50_Final.pth ${SD_BUILTIN}/repositories/CodeFormer/weights/facelib/detection_Resnet50_Final.pth
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /parsing_parsenet.pth ${SD_BUILTIN}/repositories/CodeFormer/weights/facelib/parsing_parsenet.pth

# CLIP 反向推导提示词 614M? 890M?
# https://github.com/AUTOMATIC1111/stable-diffusion-webui/discussions/10574
# COPY --from=models /model_base_caption_capfilt_large.pth ${SD_BUILTIN}/models/BLIP/model_base_caption_capfilt_large.pth 

# DeepBooru 反向推导提示词 614M
# COPY --from=models /model-resnet_custom_v3.pt ${ROOT}/models/torch_deepdanbooru/model-resnet_custom_v3.pt

# roop 554M + 
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /inswapper_128.onnx ${ROOT}/models/roop/inswapper_128.onnx
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /detector.onnx /root/.ifnude/detector.onnx
# 275M
COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /buffalo_l /root/.insightface/models
    

# controlnet 1.3G 2K 1.3G
# COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /control_v11p_sd15_scribble.pth ${ROOT}/models/ControlNet/control_v11p_sd15_scribble.pth
# COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /control_v11p_sd15_scribble.yaml ${ROOT}/models/ControlNet/control_v11p_sd15_scribble.yaml
# COPY --from=models --chown=${USER_NAME}:${GROUP_NAME} /control_v1p_sd15_illumination.safetensors ${ROOT}/models/ControlNet/control_v1p_sd15_illumination.safetensors

# adetailer 65M
COPY --from=extensions --chown=${USER_NAME}:${GROUP_NAME} /models--Bingsu--adetailer ${HOME}/root/.cache/huggingface/hub/
COPY --chown=${USER_NAME}:${GROUP_NAME} ./entrypoint.sh ${HOME}/entrypoint.sh

ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8000

WORKDIR ${ROOT}

CMD bash ${HOME}/entrypoint.sh


FROM alpine:3.17 as model-base-download

RUN apk add --no-cache aria2

RUN aria2c -x 16 --dir "/" --out "sd-v1-5-inpainting.ckpt" "https://huggingface.co/runwayml/stable-diffusion-inpainting/resolve/main/sd-v1-5-inpainting.ckpt"

RUN aria2c -x 16 --dir "/" --out "mixProV4.Cqhm.safetensors" "https://civitai.com/api/download/models/34559?type=Model&format=SafeTensor&size=full&fp=fp16"

RUN aria2c -x 16 --dir "/" --out "ChinaDollLikeness.safetensors" "https://civitai.com/api/download/models/66172?type=Model&format=SafeTensor"
RUN aria2c -x 16 --dir "/" --out "KoreanDollLikeness.safetensors" "https://civitai.com/api/download/models/31284?type=Model&format=SafeTensor&size=full&fp=fp16"
RUN aria2c -x 16 --dir "/" --out "JapaneseDollLikeness.safetensors" "https://civitai.com/api/download/models/34562?type=Model&format=SafeTensor&size=full&fp=fp16"
RUN aria2c -x 16 --dir "/" --out "chilloutmix_NiPrunedFp16Fix.safetensors" https://huggingface.co/samle/sd-webui-models/resolve/main/chilloutmix_NiPrunedFp16Fix.safetensors


RUN aria2c -x 16 --dir "/" --out "cIF8Anime2.43ol.ckpt" "https://civitai.com/api/download/models/28569"
RUN aria2c -x 16 --dir "/" --out "vae-ft-mse-840000-ema-pruned.safetensors" "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors"

RUN aria2c -x 16 --dir "/" --out "moxin.safetensors" "https://civitai.com/api/download/models/14856?type=Model&format=SafeTensor&size=full&fp=fp16" 
RUN aria2c -x 16 --dir "/" --out "blingdbox_v1_mix.safetensors" "https://civitai.com/api/download/models/32988?type=Model&format=SafeTensor&size=full&fp=fp16" 
RUN aria2c -x 16 --dir "/" --out "GachaSpliash4.safetensors" "https://civitai.com/api/download/models/38884?type=Model&format=SafeTensor" 
RUN aria2c -x 16 --dir "/" --out "Colorwater_v4.safetensors" "https://civitai.com/api/download/models/21173?type=Model&format=SafeTensor&size=full&fp=fp16" 


FROM base as model-base

# 386M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /cIF8Anime2.43ol.ckpt ${ROOT}/models/VAE/cIF8Anime2.43ol.ckpt
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /moxin.safetensors ${ROOT}/models/Lora/moxin.safetensors
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /blingdbox_v1_mix.safetensors ${ROOT}/models/Lora/blingdbox_v1_mix.safetensors
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /GachaSpliash4.safetensors ${ROOT}/models/Lora/GachaSpliash4.safetensors
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /Colorwater_v4.safetensors ${ROOT}/models/Lora/Colorwater_v4.safetensors 

RUN sed -i ${ROOT}/ui-config.json -e 's@"txt2img/Prompt/value": ""@"txt2img/Prompt/value": "masterpiece, best quality, very detailed, extremely detailed beautiful, super detailed, tousled hair, illustration, dynamic angles, girly, fashion clothing, standing, mannequin, looking at viewer, interview, beach, beautiful detailed eyes, exquisitely beautiful face, floating, high saturation, beautiful and detailed light and shadow"@'
RUN sed -i ${ROOT}/ui-config.json -e 's@"txt2img/Negative prompt/value": ""@"txt2img/Negative prompt/value": "loli,nsfw,logo,text,badhandv4,EasyNegative,ng_deepnegative_v1_75t,rev2-badprompt,verybadimagenegative_v1.3,negative_hand-neg,mutated hands and fingers,poorly drawn face,extra limb,missing limb,disconnected limbs,malformed hands,ugly"@'

FROM model-base as sd1.5
# 4G
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /sd-v1-5-inpainting.ckpt ${ROOT}/models/Stable-diffusion/sd-v1-5-inpainting.ckpt

USER ${USER_NAME}:${GROUP_NAME}

FROM model-base as anime
# 4G
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /mixProV4.Cqhm.safetensors ${ROOT}/models/Stable-diffusion/mixProV4.Cqhm.safetensors

RUN sed -i ${ROOT}/config.json -e 's/sd-v1-5-inpainting.ckpt \[c6bbc15e32\]/mixProV4.Cqhm.safetensors \[61e23e57ea\]/'
RUN sed -i ${ROOT}/config.json -e 's/c6bbc15e3224e6973459ba78de4998b80b50112b0ae5b5c67113d56b4e366b19/61e23e57ea13765152435b42d55e7062de188ca3234edb82d751cf52f7667d4f/'
RUN sed -i ${ROOT}/config.json -e 's/Automatic/cIF8Anime2.43ol.ckpt/'

USER ${USER_NAME}:${GROUP_NAME}

FROM model-base as realman
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /ChinaDollLikeness.safetensors ${ROOT}/models/Lora/ChinaDollLikeness.safetensors
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /KoreanDollLikeness.safetensors ${ROOT}/models/Lora/KoreanDollLikeness.safetensors
# 144M
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /JapaneseDollLikeness.safetensors ${ROOT}/models/Lora/JapaneseDollLikeness.safetensors
# 2G
COPY --from=model-base-download --chown=${USER_NAME}:${GROUP_NAME} /chilloutmix_NiPrunedFp16Fix.safetensors ${ROOT}/models/Stable-diffusion/chilloutmix_NiPrunedFp16Fix.safetensors

RUN sed -i ${ROOT}/config.json -e 's@sd-v1-5-inpainting.ckpt \[c6bbc15e32\]@chilloutmix_NiPrunedFp16Fix.safetensors \[59ffe2243a\]@'
RUN sed -i ${ROOT}/config.json -e 's@c6bbc15e3224e6973459ba78de4998b80b50112b0ae5b5c67113d56b4e366b19@59ffe2243a25c9fe137d590eb3c5c3d3273f1b4c86252da11bbdc9568773da0c@'

USER ${USER_NAME}:${GROUP_NAME}
