// SPDX-License-Identifier: GPL-2.0-only
/*
 * redux_exec_libretro.so — ReduxOS "launcher" libretro core.
 *
 * RetroArch cannot run shell scripts (PortMaster ports, native apps). This core accepts any .sh /
 * .desktop path as "content": on load it writes the absolute path to the per-user request file
 * ($XDG_RUNTIME_DIR/redux-exec.request, else /tmp/redux-exec-<uid>.request) and asks RetroArch to shut
 * down. The player session (~/.bash_profile, redux-session) sees the request, runs it, then starts
 * RetroArch again. Nothing runs inside RetroArch and nothing is elevated: the script runs as the same
 * unprivileged user that runs RetroArch.
 *
 * Build: tools/build-redux-exec-core.sh (cross, aarch64). Binary injected at image build, not committed.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <stdint.h>
#include <stdbool.h>
#include <fcntl.h>
#include "libretro.h"

static retro_environment_t env_cb;
static retro_video_refresh_t video_cb;
static uint16_t frame[16 * 16];

static int request_path(char *buf, size_t n)
{
	const char *rt = getenv("XDG_RUNTIME_DIR");
	if (rt && *rt)
		return snprintf(buf, n, "%s/redux-exec.request", rt) < (int)n ? 0 : -1;
	return snprintf(buf, n, "/tmp/redux-exec-%u.request", (unsigned)getuid()) < (int)n ? 0 : -1;
}

RETRO_API void retro_set_environment(retro_environment_t cb)
{
	bool no_game = false;
	env_cb = cb;
	cb(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_game);
}
RETRO_API void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
RETRO_API void retro_set_audio_sample(retro_audio_sample_t cb) { (void)cb; }
RETRO_API void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { (void)cb; }
RETRO_API void retro_set_input_poll(retro_input_poll_t cb) { (void)cb; }
RETRO_API void retro_set_input_state(retro_input_state_t cb) { (void)cb; }
RETRO_API void retro_init(void) {}
RETRO_API void retro_deinit(void) {}
RETRO_API unsigned retro_api_version(void) { return RETRO_API_VERSION; }

RETRO_API void retro_get_system_info(struct retro_system_info *info)
{
	memset(info, 0, sizeof(*info));
	info->library_name = "ReduxOS Launcher";
	info->library_version = "1.0";
	info->valid_extensions = "sh|desktop";
	info->need_fullpath = true;
	info->block_extract = true;
}

RETRO_API void retro_get_system_av_info(struct retro_system_av_info *info)
{
	memset(info, 0, sizeof(*info));
	info->geometry.base_width = info->geometry.max_width = 16;
	info->geometry.base_height = info->geometry.max_height = 16;
	info->geometry.aspect_ratio = 1.0f;
	info->timing.fps = 60.0;
	info->timing.sample_rate = 48000.0;
}

RETRO_API void retro_set_controller_port_device(unsigned port, unsigned device) { (void)port; (void)device; }
RETRO_API void retro_reset(void) {}

RETRO_API void retro_run(void)
{
	/* Normally never reached for long: shutdown was requested in retro_load_game. */
	video_cb(frame, 16, 16, 32);
	env_cb(RETRO_ENVIRONMENT_SHUTDOWN, NULL);
}

RETRO_API bool retro_load_game(const struct retro_game_info *game)
{
	char req[PATH_MAX], tmp[PATH_MAX + 8], abs[PATH_MAX];
	enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_RGB565;
	int fd;
	ssize_t len;

	if (!game || !game->path || !realpath(game->path, abs))
		return false;
	if (strchr(abs, '\n'))            /* one path per request file line; refuse odd names */
		return false;
	if (request_path(req, sizeof(req)) || snprintf(tmp, sizeof(tmp), "%s.tmp", req) >= (int)sizeof(tmp))
		return false;
	/* write-then-rename so the session never reads a half-written request; 0600, no symlink follow */
	unlink(tmp);
	fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
	if (fd < 0)
		return false;
	len = (ssize_t)strlen(abs);
	if (write(fd, abs, (size_t)len) != len || write(fd, "\n", 1) != 1 || close(fd) != 0) {
		unlink(tmp);
		return false;
	}
	if (rename(tmp, req) != 0) {
		unlink(tmp);
		return false;
	}
	env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
	env_cb(RETRO_ENVIRONMENT_SHUTDOWN, NULL);
	return true;
}

RETRO_API bool retro_load_game_special(unsigned type, const struct retro_game_info *info, size_t num)
{ (void)type; (void)info; (void)num; return false; }
RETRO_API void retro_unload_game(void) {}
RETRO_API unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }
RETRO_API void *retro_get_memory_data(unsigned id) { (void)id; return NULL; }
RETRO_API size_t retro_get_memory_size(unsigned id) { (void)id; return 0; }
RETRO_API size_t retro_serialize_size(void) { return 0; }
RETRO_API bool retro_serialize(void *data, size_t size) { (void)data; (void)size; return false; }
RETRO_API bool retro_unserialize(const void *data, size_t size) { (void)data; (void)size; return false; }
RETRO_API void retro_cheat_reset(void) {}
RETRO_API void retro_cheat_set(unsigned index, bool enabled, const char *code) { (void)index; (void)enabled; (void)code; }
