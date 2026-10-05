cmake_minimum_required(VERSION 3.25)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/UPSTREAM_VERSION" CLAUDE_CODE_UPSTREAM LIMIT_COUNT 1)
set(CLAUDE_CODE_VERSION "${CLAUDE_CODE_UPSTREAM}")
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" CLAUDE_CODE_VERSION LIMIT_COUNT 1)
endif()

project(ClaudeCode LANGUAGES C OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)
include(MavericksMode)
mavericks_build_mode(MAVERICKS_MODE)
mavericks_require_expected_mode("${MAVERICKS_MODE}")
message(STATUS "Claude Code ${CLAUDE_CODE_VERSION}: build mode ${MAVERICKS_MODE}")

option(CLAUDE_CODE_BUILD_UPDATER "Build the Sparkle updater (needs claude-code in the installed shipyard's product registry)" OFF)

if(CLAUDE_CODE_BUILD_UPDATER)
  include(MavericksSparkle)
  mavericks_add_updater_app(
    PRODUCT claude-code
    PRODUCT_NAME "Mavericks Claude Code"
    ALLOW_GENERIC
    VERSION "${CLAUDE_CODE_VERSION}"
    CONFIRM_TITLE "Mavericks Claude Code updated"
    CONFIRM_BODY "The next claude you start uses the new launcher.")
endif()
