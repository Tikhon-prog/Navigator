#!/usr/bin/env bash
# Собирает llama.cpp/ggml для CPU БЕЗ AVX/AVX2/FMA (для Celeron/Atom и старых
# процессоров: готовая libggml-cpu.so из пакета падает с «illegal instruction»).
# Результат: linux/native_cpu/lib{llama,ggml,ggml-base,ggml-cpu}.so — сборка
# Linux подставляет их в bundle вместо готовых.
# Запуск: bash tool/build_llama_cpu.sh
# Нужны: git cmake g++ (sudo apt install git cmake g++). Время: 5-20 минут.
set -euo pipefail

# Коммит llama.cpp, под который собран llm_llamacpp 0.7.0 (ABI должен совпадать).
COMMIT=25ae3a9b331fffea50ff8d07a5cad34c33f1276f
JOBS="${JOBS:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${TMPDIR:-/tmp}/llama.cpp-$COMMIT"
OUT="$ROOT/linux/native_cpu"

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
if ! git -C "$SRC" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch --depth 1 origin "$COMMIT"
fi
git -C "$SRC" checkout -q "$COMMIT"

cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON -DGGML_NATIVE=OFF \
  -DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF \
  -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF \
  -DGGML_CUDA=OFF -DGGML_VULKAN=OFF -DGGML_OPENMP=OFF \
  -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_TOOLS=OFF
cmake --build "$SRC/build" --target llama -j"$JOBS"

mkdir -p "$OUT"
rm -f "$OUT"/lib*.so
for name in llama ggml ggml-base ggml-cpu; do
  file="$(find "$SRC/build" -name "lib$name.so" | head -n1)"
  [ -n "$file" ] || { echo "Не найден lib$name.so" >&2; exit 1; }
  cp -L "$file" "$OUT/lib$name.so"
done

echo "Готово: $OUT"
ls -l "$OUT"
echo "Инструкций AVX (ymm) в libggml-cpu.so: $(objdump -d "$OUT/libggml-cpu.so" | grep -c ymm || true) (должно быть 0)"
