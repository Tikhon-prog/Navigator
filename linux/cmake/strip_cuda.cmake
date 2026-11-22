# Готовые библиотеки llama.cpp/ggml из llm_llamacpp собраны с CUDA: libggml
# зависит от libggml-cuda.so, а тот — от libcudart.so.12. Без CUDA-toolkit
# (видеокарта не NVIDIA) загрузка падает с «libcudart.so.12: cannot open
# shared object file», и нейросеть не запускается. Нейросети хватает CPU.
#
# Скрипт запускается на этапе install. Если libcudart.so.12 в системе есть,
# ничего не делает. Если нет — удаляет CUDA-бэкенд из bundle и убирает записи
# NEEDED о CUDA из остальных библиотек (нужен patchelf: sudo apt install patchelf).
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib.

set(_cuda_found FALSE)

execute_process(
  COMMAND ldconfig -p
  OUTPUT_VARIABLE _ldconfig
  ERROR_QUIET
  RESULT_VARIABLE _ldconfig_result)
if(_ldconfig_result EQUAL 0 AND _ldconfig MATCHES "libcudart\\.so\\.12")
  set(_cuda_found TRUE)
endif()

if(NOT _cuda_found)
  file(GLOB _cuda_runtime
    "/usr/local/cuda*/lib64/libcudart.so.12*"
    "/usr/lib/x86_64-linux-gnu/libcudart.so.12*")
  if(_cuda_runtime)
    set(_cuda_found TRUE)
  endif()
endif()

if(_cuda_found)
  message(STATUS "CUDA runtime найден, библиотеки llama/ggml не меняются")
  return()
endif()

message(STATUS "CUDA runtime не найден: убираю CUDA-бэкенд из bundle (нейросеть работает на CPU)")

# 1. Удаляем сами CUDA-бэкенды.
file(GLOB _cuda_backends "${BUNDLE_LIB_DIR}/libggml-cuda*")
foreach(_file IN LISTS _cuda_backends)
  message(STATUS "Удалён ${_file}")
  file(REMOVE "${_file}")
endforeach()

# 2. Убираем из оставшихся библиотек зависимости от CUDA.
find_program(_patchelf patchelf)
file(GLOB _native_libs "${BUNDLE_LIB_DIR}/lib*.so*")

foreach(_lib IN LISTS _native_libs)
  if(IS_SYMLINK "${_lib}")
    continue()
  endif()
  execute_process(
    COMMAND readelf -d "${_lib}"
    OUTPUT_VARIABLE _dynamic
    ERROR_QUIET
    RESULT_VARIABLE _readelf_result)
  if(NOT _readelf_result EQUAL 0)
    continue()
  endif()

  string(REGEX MATCHALL "\\(NEEDED\\)[ ]+Shared library: \\[[^]]+\\]" _needed "${_dynamic}")
  foreach(_entry IN LISTS _needed)
    string(REGEX REPLACE ".*\\[([^]]+)\\]" "\\1" _dep "${_entry}")
    if(_dep MATCHES "^(libcudart|libcublas|libcublasLt|libcuda|libnvrtc|libggml-cuda)")
      get_filename_component(_name "${_lib}" NAME)
      if(_patchelf)
        message(STATUS "${_name}: убрана зависимость ${_dep}")
        execute_process(
          COMMAND "${_patchelf}" --remove-needed "${_dep}" "${_lib}"
          ERROR_QUIET)
      else()
        message(WARNING
          "${_name} зависит от ${_dep}, а patchelf не установлен. "
          "Выполните: sudo apt install patchelf — и пересоберите.")
      endif()
    endif()
  endforeach()
endforeach()
