# Готовые библиотеки llama.cpp/ggml из llm_llamacpp собраны с CUDA: libggml.so
# вызывает ggml_backend_cuda_reg() из libggml-cuda.so, а тот зависит от
# libcudart.so.12. Без CUDA-toolkit (видеокарта не NVIDIA) загрузка падает.
# Просто удалить libggml-cuda.so нельзя: libggml.so остаётся с неразрешённым
# символом и процесс вылетает.
#
# Если libcudart.so.12 в системе нет, скрипт заменяет libggml-cuda.so заглушкой
# с тем же SONAME: ggml_backend_cuda_reg() возвращает NULL («CUDA-устройств нет»),
# а нейросеть работает на CPU. Если CUDA есть, ничего не меняется.
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib, CXX_COMPILER — компилятор C++.

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

message(STATUS "CUDA runtime не найден: заменяю CUDA-бэкенд заглушкой (нейросеть на CPU)")

if(NOT CXX_COMPILER)
  set(CXX_COMPILER "c++")
endif()

# 1. Находим настоящий CUDA-бэкенд и запоминаем его имя и SONAME.
set(_stub_name "")
set(_stub_soname "")
file(GLOB _cuda_backends "${BUNDLE_LIB_DIR}/libggml-cuda*")
foreach(_file IN LISTS _cuda_backends)
  if(NOT IS_SYMLINK "${_file}" AND _file MATCHES "\\.so$")
    get_filename_component(_stub_name "${_file}" NAME)
    execute_process(
      COMMAND readelf -d "${_file}"
      OUTPUT_VARIABLE _dynamic
      ERROR_QUIET)
    string(REGEX MATCH "Library soname: \\[([^]]+)\\]" _match "${_dynamic}")
    if(_match)
      set(_stub_soname "${CMAKE_MATCH_1}")
    endif()
  endif()
endforeach()

# 2. Удаляем настоящий CUDA-бэкенд (и ссылки на него).
foreach(_file IN LISTS _cuda_backends)
  message(STATUS "Удалён ${_file}")
  file(REMOVE "${_file}")
endforeach()

# 3. Собираем заглушку с тем же именем и SONAME.
if(_stub_name)
  if(NOT _stub_soname)
    set(_stub_soname "${_stub_name}")
  endif()
  set(_stub_src "${BUNDLE_LIB_DIR}/ggml_cuda_stub.cpp")
  file(WRITE "${_stub_src}" "
extern \"C\" {
void* ggml_backend_cuda_reg(void) { return 0; }
void* ggml_backend_cuda_init(int) { return 0; }
bool  ggml_backend_is_cuda(void*) { return false; }
void* ggml_backend_cuda_buffer_type(int) { return 0; }
void* ggml_backend_cuda_split_buffer_type(int, const float*) { return 0; }
void* ggml_backend_cuda_host_buffer_type(void) { return 0; }
int   ggml_backend_cuda_get_device_count(void) { return 0; }
void  ggml_backend_cuda_get_device_description(int, char*, unsigned long) {}
void  ggml_backend_cuda_get_device_memory(int, unsigned long*, unsigned long*) {}
bool  ggml_backend_cuda_register_host_buffer(void*, unsigned long) { return false; }
void  ggml_backend_cuda_unregister_host_buffer(void*) {}
}
")
  execute_process(
    COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
            "-Wl,-soname,${_stub_soname}"
            -o "${BUNDLE_LIB_DIR}/${_stub_name}" "${_stub_src}"
    RESULT_VARIABLE _stub_result
    ERROR_VARIABLE _stub_error)
  file(REMOVE "${_stub_src}")
  if(_stub_result EQUAL 0)
    message(STATUS "Создана заглушка ${_stub_name} (SONAME ${_stub_soname})")
  else()
    message(WARNING "Не удалось собрать заглушку CUDA: ${_stub_error}")
  endif()
endif()

# 4. Прямые зависимости остальных библиотек от CUDA-runtime (если есть).
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
    if(_dep MATCHES "^(libcudart|libcublas|libcublasLt|libcuda|libnvrtc)")
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
