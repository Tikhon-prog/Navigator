# Vulkan-бэкенд ggml (libggml-vulkan.so) находит видеокарту (например, Intel UHD
# Graphics 600 на Mesa) и роняет программу при инициализации. Нейросети хватает
# CPU, поэтому libggml-vulkan.so заменяется заглушкой с тем же именем и SONAME:
# функции возвращают «устройств нет», а ggml_backend_init в ней нет, так что
# динамическая загрузка бэкенда тихо пропускается.
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib, CXX_COMPILER — компилятор C++.

file(GLOB _vk_backends "${BUNDLE_LIB_DIR}/libggml-vulkan*")
if(NOT _vk_backends)
  message(STATUS "Vulkan-бэкенд ggml в bundle не найден, ничего не меняю")
  return()
endif()

if(NOT CXX_COMPILER)
  set(CXX_COMPILER "c++")
endif()

set(_vk_name "")
set(_vk_soname "")
foreach(_file IN LISTS _vk_backends)
  if(_file MATCHES "\\.so$")
    get_filename_component(_vk_name "${_file}" NAME)
    execute_process(COMMAND readelf -d "${_file}"
      OUTPUT_VARIABLE _dynamic ERROR_QUIET)
    string(REGEX MATCH "Library soname: \\[([^]]+)\\]" _match "${_dynamic}")
    if(_match)
      set(_vk_soname "${CMAKE_MATCH_1}")
    endif()
  endif()
endforeach()
foreach(_file IN LISTS _vk_backends)
  file(REMOVE "${_file}")
endforeach()

if(NOT _vk_name)
  set(_vk_name "libggml-vulkan.so")
endif()
if(NOT _vk_soname)
  set(_vk_soname "${_vk_name}")
endif()

set(_vk_src "${BUNDLE_LIB_DIR}/ggml_vulkan_stub.cpp")
file(WRITE "${_vk_src}" "
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
execute_process(COMMAND "${CXX_COMPILER}" -shared -fPIC -O1
  "-Wl,-soname,${_vk_soname}" -o "${BUNDLE_LIB_DIR}/${_vk_name}" "${_vk_src}"
  RESULT_VARIABLE _result ERROR_VARIABLE _error)
file(REMOVE "${_vk_src}")
if(_result EQUAL 0)
  message(STATUS "Vulkan отключён: заглушка ${_vk_name} (SONAME ${_vk_soname})")
else()
  message(WARNING "Не удалось собрать заглушку Vulkan: ${_error}")
endif()
