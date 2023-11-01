#!/bin/bash

set -Eeuox pipefail

bash /home/paas/mount.sh &

python webui.py --xformers --port 8000 --listen \
--skip-prepare-environment --no-download-sd-model \
--ckpt-dir /mnt/auto/sd/models/Stable-diffusion \
--vae-dir /mnt/auto/sd/models/VAE \
--lora-dir /mnt/auto/sd/models/Lora \
--codeformer-models-path /mnt/auto/sd/models/Codeformer \
--gfpgan-models-path /mnt/auto/sd/models/GFPGAN \
--esrgan-models-path /mnt/auto/sd/models/ESRGAN \
--bsrgan-models-path /mnt/auto/sd/models/BSRGAN \
--realesrgan-models-path /mnt/auto/sd/models/RealESRGAN \
--embeddings-dir /mnt/auto/sd/embeddings
