# GPU-бэкенды ggml (Vulkan, CUDA) нейросети не нужны: хватает CPU. Хуже того,
# libggml.so ищет libggml-vulkan.so.0 / libggml-cuda.so.0 по SONAME и может
# подхватить чужие версии из /usr/local/lib; они находят видеокарту (Intel UHD
# на Mesa) и роняют процесс. Для каждого бэкенда кладём в bundle заглушку с
# SONAME libggml-<backend>.so.0: функции возвращают «устройств нет»
# (ggml_backend_*_reg() == NULL). Приложение загружает заглушки первыми, и
# загрузчик берёт их вместо системных библиотек.
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib, CXX_COMPILER — компилятор C++.

if(NOT CXX_COMPILER)
  set(CXX_COMPILER "c++")
endif()

set(_stub_vulkan "
extern \"C\" {
void* ggml_backend_vk_reg(void) { return 0; }
void* ggml_backend_vk_init(unsigned long) { return 0; }
bool  ggml_backend_is_vk(void*) { return false; }
int   ggml_backend_vk_get_device_count(void) { return 0; }
void  ggml_backend_vk_get_device_description(int, char*, unsigned long) {}
void  ggml_backend_vk_get_device_memory(int, unsigned long*, unsigned long*) {}
void* ggml_backend_vk_buffer_type(unsigned long) { return 0; }
void* ggml_backend_vk_host_buffer_type(void) { return 0; }
}
")

set(_stub_cuda "
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

foreach(_backend IN ITEMS vulkan cuda)
  # Настоящие библиотеки бэкенда из bundle убираем.
  file(GLOB _old "${BUNDLE_LIB_DIR}/libggml-${_backend}*")
  foreach(_file IN LISTS _old)
    file(REMOVE "${_file}")
  endforeach()

  set(_name "libggml-${_backend}.so.0")
  set(_src "${BUNDLE_LIB_DIR}/ggml_${_backend}_stub.cpp")
  file(WRITE "${_src}" "${_stub_${_backend}}")
  execute_process(COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
    "-Wl,-soname,${_name}" -o "${BUNDLE_LIB_DIR}/${_name}" "${_src}"
    RESULT_VARIABLE _result ERROR_VARIABLE _error)
  file(REMOVE "${_src}")
  if(_result EQUAL 0)
    message(STATUS "GPU-бэкенд ${_backend} отключён: заглушка ${_name}")
  else()
    message(WARNING "Не удалось собрать заглушку ${_name}: ${_error}")
  endif()
endforeach()
