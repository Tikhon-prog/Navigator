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

# Нужен ли libcudart.so.12: ищем библиотеки bundle, которым он нужен, и
# смотрим через ldd, находит ли загрузчик. Строка «not found» = CUDA нет.
file(GLOB _libs "${BUNDLE_LIB_DIR}/lib*.so*")
set(_cuda_missing FALSE)
find_program(_ldd ldd)
if(_ldd)
  foreach(_lib IN LISTS _libs)
    if(IS_SYMLINK "${_lib}")
      continue()
    endif()
    execute_process(COMMAND "${_ldd}" "${_lib}"
      OUTPUT_VARIABLE _ldd_out ERROR_QUIET)
    if(_ldd_out MATCHES "libcudart[^\n]*not found")
      set(_cuda_missing TRUE)
    endif()
  endforeach()
else()
  file(GLOB _cudart "/usr/local/cuda*/lib64/libcudart.so.12*"
    "/usr/lib/x86_64-linux-gnu/libcudart.so.12*")
  if(NOT _cudart)
    set(_cuda_missing TRUE)
  endif()
endif()

if(NOT _cuda_missing)
  message(STATUS "CUDA runtime найден, библиотеки llama/ggml не меняются")
  return()
endif()

message(STATUS "CUDA runtime не найден: ставлю заглушки (нейросеть на CPU)")

if(NOT CXX_COMPILER)
  set(CXX_COMPILER "c++")
endif()

# 0. Заглушка libcudart.so.12: libggml/libllama требуют её напрямую. Она
# экспортирует все cuda*-символы, которые нужны библиотекам bundle, и
# возвращает 0. Нейросеть при этом работает на CPU.
set(_cu_syms "")
foreach(_lib IN LISTS _libs)
  if(IS_SYMLINK "${_lib}")
    continue()
  endif()
  execute_process(COMMAND nm -D --undefined-only "${_lib}"
    OUTPUT_VARIABLE _nm ERROR_QUIET)
  string(REGEX MATCHALL "U (cuda|__cuda)[A-Za-z0-9_]+" _found "${_nm}")
  list(APPEND _cu_syms ${_found})
endforeach()
list(REMOVE_DUPLICATES _cu_syms)
set(_cu_body "")
foreach(_sym IN LISTS _cu_syms)
  string(REPLACE "U " "" _cu_name "${_sym}")
  string(APPEND _cu_body "extern \"C\" int ${_cu_name}(void) { return 0; }\n")
endforeach()
set(_cu_src "${BUNDLE_LIB_DIR}/cudart_stub.cpp")
file(WRITE "${_cu_src}" "${_cu_body}")
execute_process(COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
  "-Wl,-soname,libcudart.so.12"
  -o "${BUNDLE_LIB_DIR}/libcudart.so.12" "${_cu_src}"
  RESULT_VARIABLE _cu_result ERROR_VARIABLE _cu_error)
file(REMOVE "${_cu_src}")
if(_cu_result EQUAL 0)
  list(LENGTH _cu_syms _cu_count)
  message(STATUS "Создана заглушка libcudart.so.12 (символов: ${_cu_count})")
else()
  message(WARNING "Не удалось собрать заглушку libcudart: ${_cu_error}")
endif()

# 1. Находим настоящий CUDA-бэкенд и запоминаем его имя и SONAME.
set(_stub_name "")
set(_stub_soname "")
file(GLOB _cuda_backends "${BUNDLE_LIB_DIR}/libggml-cuda*")
foreach(_file IN LISTS _cuda_backends)
  if(_file MATCHES "\\.so$")
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

