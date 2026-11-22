# Нативные библиотеки llama.cpp/ggml собраны с SONAME вида «libggml.so.0»,
# а сборочный hook кладёт их в bundle/lib под именем «libggml.so» (ссылки
# «.so.0» из архива он пропускает). Из-за этого загрузчик не находит
# зависимости libllama.so. Здесь для каждой библиотеки создаётся ссылка с её
# настоящим SONAME. Скрипт запускается на этапе install и не требует ручных
# действий от пользователя.
#
# Вход: BUNDLE_LIB_DIR — папка bundle/lib.

file(GLOB _native_libs "${BUNDLE_LIB_DIR}/lib*.so")

foreach(_lib IN LISTS _native_libs)
  get_filename_component(_name "${_lib}" NAME)
  set(_soname "")

  execute_process(
    COMMAND readelf -d "${_lib}"
    OUTPUT_VARIABLE _dynamic
    ERROR_QUIET
    RESULT_VARIABLE _readelf_result)
  if(_readelf_result EQUAL 0)
    string(REGEX MATCH "Library soname: \\[([^]]+)\\]" _match "${_dynamic}")
    if(_match)
      set(_soname "${CMAKE_MATCH_1}")
    endif()
  endif()

  # Запасной вариант, если readelf недоступен: у llama.cpp SONAME — это имя
  # файла с суффиксом «.0».
  if(NOT _soname AND _name MATCHES "^lib(llama|ggml)")
    set(_soname "${_name}.0")
  endif()

  if(_soname AND NOT _soname STREQUAL _name
     AND NOT EXISTS "${BUNDLE_LIB_DIR}/${_soname}")
    message(STATUS "SONAME: ${_soname} -> ${_name}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E create_symlink "${_name}"
              "${BUNDLE_LIB_DIR}/${_soname}")
  endif()
endforeach()
