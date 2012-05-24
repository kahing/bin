#if 0
gcc $0 -shared -o $0.so -ldl -fPIC && LD_PRELOAD=$0.so exec $@
#else

/** 
 * cleancache.c - drop files content from page cache after use
 *
 * This is intended to be a library that you LD_PRELOAD into existing
 * (ex: backup) commands. One can also chmod +x this file and then
 * prefix other command invocations with it assuming gcc is installed:
 *
 * $ path/to/cleancache.c <cmd>
 *
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version
 * 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301 USA
 *
 *
 * TODO: hook read/write too to allow memory to be dropped earlier
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>

int close(int fd)
{
    static int (*close_func)(int) = NULL;
    if (close_func == NULL) {
        close_func = dlsym(RTLD_NEXT, "close");
    }

    posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED);

    return close_func(fd);
}

#endif
