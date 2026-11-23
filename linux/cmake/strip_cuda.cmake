# Готовые libggml.so/libllama.so из llm_llamacpp собраны с CUDA и напрямую
# требуют libcudart.so.12, libcublas.so.12, libcublasLt.so.12 и т.п. Без
# CUDA-toolkit (видеокарта не NVIDIA) загрузка падает. Скрипт для каждой
# такой ненайденной библиотеки собирает заглушку с тем же SONAME, которая
# экспортирует нужные cuda*/cublas*/cu*/nvrtc* символы (возвращают 0).
# Приложение загружает заглушки первыми, нейросеть работает на CPU.
# Дополнительно libggml-cuda.so заменяется заглушкой ggml_backend_cuda_reg()
# (возвращает NULL, «CUDA-устройств нет»).
# Если CUDA в системе есть, ничего не меняется.
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib, CXX_COMPILER — компилятор C++.

file(GLOB _libs "${BUNDLE_LIB_DIR}/lib*.so*")

# 1. Какие CUDA-библиотеки загрузчик не находит (по выводу ldd).
set(_missing "")
find_program(_ldd ldd)
if(_ldd)
  foreach(_lib IN LISTS _libs)
    if(IS_SYMLINK "${_lib}")
      continue()
    endif()
    execute_process(COMMAND "${_ldd}" "${_lib}"
      OUTPUT_VARIABLE _ldd_out ERROR_QUIET)
    string(REGEX MATCHALL "lib(cu|nv)[A-Za-z0-9_+-]*\\.so[.0-9]*[ \t]+=>[ \t]+not found"
      _found "${_ldd_out}")
    foreach(_entry IN LISTS _found)
      string(REGEX REPLACE "[ \t]+=>.*" "" _entry "${_entry}")
      list(APPEND _missing "${_entry}")
    endforeach()
  endforeach()
  list(REMOVE_DUPLICATES _missing)
endif()

if(NOT _missing)
  message(STATUS "Все CUDA-зависимости найдены (или не нужны): библиотеки не меняются")
  return()
endif()

message(STATUS "CUDA не найден (${_missing}): ставлю заглушки, нейросеть на CPU")

if(NOT CXX_COMPILER)
  set(CXX_COMPILER "c++")
endif()

# 2. Какие символы CUDA нужны библиотекам bundle.
set(_syms "")
foreach(_lib IN LISTS _libs)
  if(IS_SYMLINK "${_lib}")
    continue()
  endif()
  execute_process(COMMAND nm -D --undefined-only "${_lib}"
    OUTPUT_VARIABLE _nm ERROR_QUIET)
  string(REGEX MATCHALL
    "U (cuda|__cuda|cublas|cu[A-Z]|nvrtc|nvml)[A-Za-z0-9_]*" _found "${_nm}")
  list(APPEND _syms ${_found})
endforeach()
list(REMOVE_DUPLICATES _syms)
set(_body "")
foreach(_sym IN LISTS _syms)
  string(REPLACE "U " "" _name "${_sym}")
  string(APPEND _body "extern \"C\" int ${_name}(void) { return 0; }\n")
endforeach()
list(LENGTH _syms _count)

# 3. По заглушке на каждую ненайденную библиотеку (имя = SONAME).
set(_src "${BUNDLE_LIB_DIR}/cuda_stub.cpp")
file(WRITE "${_src}" "${_body}")
foreach(_stub IN LISTS _missing)
  execute_process(COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
    "-Wl,-soname,${_stub}" -o "${BUNDLE_LIB_DIR}/${_stub}" "${_src}"
    RESULT_VARIABLE _result ERROR_VARIABLE _error)
  if(_result EQUAL 0)
    message(STATUS "Создана заглушка ${_stub} (символов: ${_count})")
  else()
    message(WARNING "Не удалось собрать заглушку ${_stub}: ${_error}")
  endif()
endforeach()
file(REMOVE "${_src}")

# 4. CUDA-бэкенд ggml заменяем заглушкой с тем же именем и SONAME.
set(_ggml_name "")
set(_ggml_soname "")
file(GLOB _cuda_backends "${BUNDLE_LIB_DIR}/libggml-cuda*")
foreach(_file IN LISTS _cuda_backends)
  if(_file MATCHES "\\.so$")
    get_filename_component(_ggml_name "${_file}" NAME)
    execute_process(COMMAND readelf -d "${_file}"
      OUTPUT_VARIABLE _dynamic ERROR_QUIET)
    string(REGEX MATCH "Library soname: \\[([^]]+)\\]" _match "${_dynamic}")
    if(_match)
      set(_ggml_soname "${CMAKE_MATCH_1}")
    endif()
  endif()
endforeach()
foreach(_file IN LISTS _cuda_backends)
  file(REMOVE "${_file}")
endforeach()

if(_ggml_name)
  if(NOT _ggml_soname)
    set(_ggml_soname "${_ggml_name}")
  endif()
  set(_ggml_src "${BUNDLE_LIB_DIR}/ggml_cuda_stub.cpp")
  file(WRITE "${_ggml_src}" "
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
  execute_process(COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
    "-Wl,-soname,${_ggml_soname}"
    -o "${BUNDLE_LIB_DIR}/${_ggml_name}" "${_ggml_src}"
    RESULT_VARIABLE _result ERROR_VARIABLE _error)
  file(REMOVE "${_ggml_src}")
  if(_result EQUAL 0)
    message(STATUS "Создана заглушка ${_ggml_name} (SONAME ${_ggml_soname})")
  else()
    message(WARNING "Не удалось собрать заглушку ${_ggml_name}: ${_error}")
  endif()
endif()
