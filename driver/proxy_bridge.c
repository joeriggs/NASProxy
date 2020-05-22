/*
  FUSE: Filesystem in Userspace
  Copyright (C) 2001-2007  Miklos Szeredi <miklos@szeredi.hu>

  This program can be distributed under the terms of the GNU GPL.
  See the file COPYING.
*/

#define _GNU_SOURCE
#define FUSE_USE_VERSION 30

#include <fuse3/fuse_lowlevel.h>

#include <assert.h>
#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include <sys/fsuid.h>
#include <sys/types.h>

#include <attr/xattr.h> // Needed for extended attributes.

#define PROCFS_LINK_SZ (64)

struct lo_inode {
	struct lo_inode *next;
	struct lo_inode *prev;
	int fd;
	bool is_symlink;
	ino_t ino;
	dev_t dev;
	uint64_t nlookup;
};

struct lo_data {
	int debug;
	struct lo_inode root;
};

/* Used by opendir/readdir(plus)/closedir to keep track of the state. */
struct lo_dirp {
	int fd;
	DIR *dp;
	struct dirent *entry;
	off_t offset;
};

/* *****************************************************************************
 * Logging.
 * ****************************************************************************/

static int logToSyslog = 0;
static void logMsg(fuse_req_t req, const char *func, int priority, const char *fmt, ...)
{
	char fmtBuf[1024];
	if(req != NULL) {
		const struct fuse_ctx *ctx = fuse_req_ctx(req);
		snprintf(fmtBuf, sizeof(fmtBuf), "[%s] (%d %d %d): %s\n", func,
		         ctx->uid, ctx->gid, ctx->pid, fmt);
	}
	else {
		snprintf(fmtBuf, sizeof(fmtBuf), "[%s]: %s\n", func, fmt);
	}

	va_list args;
	va_start(args, fmt);
	if(logToSyslog) {
		vsyslog(priority, fmtBuf, args);
	}
	else {
		vfprintf(stderr, fmtBuf, args);
	}
	va_end(args);
}

#define LOG_ENTER(req, fmt, ...) { \
	int u = 0, g = 0, p = 0; \
	if(req != NULL) { \
		const struct fuse_ctx *ctx = fuse_req_ctx(req); \
		u = ctx->uid; \
		g = ctx->gid; \
		p = ctx->pid; \
	} \
	logMsg(req, __func__, LOG_INFO, "ENTER: (%d %d %d) " fmt, u, g, p, ##__VA_ARGS__); \
	setfsuid(u); \
	setfsgid(g); \
}
#define LOG_EXIT(req, fmt, ...)  logMsg(req, __func__, LOG_INFO, "EXIT: " fmt, ##__VA_ARGS__)
#define LOG_TRACE(req, fmt, ...) logMsg(req, __func__, LOG_INFO, fmt, ##__VA_ARGS__)
#define LOG_ERROR(req, fmt, ...) logMsg(req, __func__, LOG_INFO, "ERROR: " fmt, ##__VA_ARGS__)

/* This function returns a string that describes the access mode for a file.
 *  */
static const char *fuseAccessModeToString(int flags)
{
	static __thread char str[1024];
	memset(str, 0, sizeof(str));

	if((flags & O_CREAT)     == O_CREAT)     { strcat(str, " CREAT");     }
	if((flags & O_EXCL)      == O_EXCL)      { strcat(str, " EXCL");      }
	if((flags & O_NOCTTY)    == O_NOCTTY)    { strcat(str, " NOCTTY");    }
	if((flags & O_TRUNC)     == O_TRUNC)     { strcat(str, " TRUNC");     }
	if((flags & O_APPEND)    == O_APPEND)    { strcat(str, " APPEND");    }
	if((flags & O_NONBLOCK)  == O_NONBLOCK)  { strcat(str, " NONBLOCK");  }
	if((flags & O_SYNC)      == O_SYNC)      { strcat(str, " SYNC");      }
	if((flags & O_DIRECT)    == O_DIRECT)    { strcat(str, " DIRECT");    }
	if((flags & O_ASYNC)     == O_ASYNC)     { strcat(str, " ASYNC");     }
	if((flags & O_LARGEFILE) == O_LARGEFILE) { strcat(str, " LARGEFILE"); }
	if((flags & O_DIRECTORY) == O_DIRECTORY) { strcat(str, " DIRECTORY"); }
	if((flags & O_NOFOLLOW)  == O_NOFOLLOW)  { strcat(str, " NOFOLLOW");  }
	if((flags & O_NOATIME)   == O_NOATIME)   { strcat(str, " NOATIME");   }
	if((flags & O_CLOEXEC)   == O_CLOEXEC)   { strcat(str, " CLOEXEC");   }

	int accmode = flags & O_ACCMODE;
	if(     accmode == O_RDONLY)             { strcat(str, " (RDONLY)");  }
	else if(accmode == O_WRONLY)             { strcat(str, " (WRONLY)");  }
	else if(accmode == O_RDWR)               { strcat(str, " (RDWR)");    }
	else                                     { strcat(str, " (UNKNOWN)"); }

	return str;
}


static char *modeToString(mode_t mode)
{
	static __thread char modeString[2048];
	modeString[0] = 0;

	if(S_ISLNK(mode))  { strcat(modeString, "LNK ");  }
	if(S_ISREG(mode))  { strcat(modeString, "REG ");  }
	if(S_ISDIR(mode))  { strcat(modeString, "DIR ");  }
	if(S_ISCHR(mode))  { strcat(modeString, "CHR ");  }
	if(S_ISBLK(mode))  { strcat(modeString, "BLK ");  }
	if(S_ISFIFO(mode)) { strcat(modeString, "FIFO "); }
	if(S_ISSOCK(mode)) { strcat(modeString, "SOCK "); }

	strcat(modeString, (mode & S_IRUSR) ? "r" : "-");
	strcat(modeString, (mode & S_IWUSR) ? "w" : "-");
	strcat(modeString, (mode & S_IXUSR) ? "x" : "-");

	strcat(modeString, (mode & S_IRGRP) ? "r" : "-");
	strcat(modeString, (mode & S_IWGRP) ? "w" : "-");
	strcat(modeString, (mode & S_IWGRP) ? "x" : "-");

	strcat(modeString, (mode & S_IROTH) ? "r" : "-");
	strcat(modeString, (mode & S_IWOTH) ? "w" : "-");
	strcat(modeString, (mode & S_IXOTH) ? "x" : "-");

	return modeString;
}
/* *****************************************************************************
 * PRIVATE UTILITY FUNCTIONS.
 * ****************************************************************************/

/* Get the symbolic link of an fd. */
static void linkFromFD(int fd, char *linkName, size_t linkSize)
{
	snprintf(linkName, linkSize, "/proc/self/fd/%i", fd);
}

/* Get the full path of a file from its fd.
 *
 * Retcode:
 * >0 = length of the pathname.
 * -1 = failure (errno = reason for failure).
 */
static int pathFromFD(int fd, char *pathName, size_t pathSize)
{
	char linkName[PROCFS_LINK_SZ];
	linkFromFD(fd, linkName, sizeof(linkName));

	memset(pathName, 0, pathSize);
	return readlink(linkName, pathName, pathSize);
}

static struct lo_data *lo_data(fuse_req_t req)
{
	return (struct lo_data *) fuse_req_userdata(req);
}

static struct lo_inode *lo_inode(fuse_req_t req, fuse_ino_t ino)
{
	if (ino == FUSE_ROOT_ID)
		return &lo_data(req)->root;
	else
		return (struct lo_inode *) (uintptr_t) ino;
}

static int lo_fd(fuse_req_t req, fuse_ino_t ino)
{
	return lo_inode(req, ino)->fd;
}

static struct lo_inode *lo_find(struct lo_data *lo, struct stat *st)
{
	struct lo_inode *p;

	for (p = lo->root.next; p != &lo->root; p = p->next) {
		if (p->ino == st->st_ino && p->dev == st->st_dev)
			return p;
	}
	return NULL;
}

/*
 * Returns:
 *   0 = success
 *  !0 = errno of failure.
 */
static int lo_do_lookup(fuse_req_t req, fuse_ino_t parent, const char *name,
                        struct fuse_entry_param *e)
{
	int newfd;
	int res;
	int saverr;
	struct lo_inode *inode;

	memset(e, 0, sizeof(*e));
	e->attr_timeout = 1.0;
	e->entry_timeout = 1.0;

	newfd = openat(lo_fd(req, parent), name, O_PATH | O_NOFOLLOW);
	if (newfd == -1) {
		saverr = errno;
		LOG_TRACE(req, "openat() failed (%m).");
		errno = saverr;
		goto out_err;
	}

	res = fstatat(newfd, "", &e->attr, AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW);
	if (res == -1) {
		saverr = errno;
		LOG_ERROR(req, "fstatat() failed (%m).");
		errno = saverr;
		goto out_err;
	}

	inode = lo_find(lo_data(req), &e->attr);
	if (inode) {
		close(newfd);
		newfd = -1;
	} else {
		struct lo_inode *prev = &lo_data(req)->root;
		struct lo_inode *next = prev->next;
		saverr = ENOMEM;
		inode = calloc(1, sizeof(struct lo_inode));
		if (!inode)
			goto out_err;

		inode->is_symlink = S_ISLNK(e->attr.st_mode);
		inode->fd = newfd;
		inode->ino = e->attr.st_ino;
		inode->dev = e->attr.st_dev;

		next->prev = inode;
		inode->next = next;
		inode->prev = prev;
		prev->next = inode;
	}
	inode->nlookup++;
	e->ino = (uintptr_t) inode;

	LOG_TRACE(req, "%lli/%s -> %lli: fd %d: dev/ino %d/%d.",
	          (unsigned long long) parent, name, (unsigned long long) e->ino, inode->fd,
	          inode->dev, inode->ino);

	return 0;

out_err:
	saverr = errno;
	if (newfd != -1)
		close(newfd);
	return saverr;
}

static void lo_free(struct lo_inode *inode)
{
	struct lo_inode *prev = inode->prev;
	struct lo_inode *next = inode->next;

	next->prev = prev;
	prev->next = next;
	close(inode->fd);
	free(inode);
}

/* Get the lo_dirp data structure that is being used to manage the multiple
 * calls required by opendir/readdir/closedir. */
static struct lo_dirp *lo_dirp(struct fuse_file_info *fi)
{
	return (struct lo_dirp *) (uintptr_t) fi->fh;
}

/* The main processing of both readdir and readdirplus operations. */
static void lo_do_readdir(fuse_req_t req, fuse_ino_t ino, size_t size,
			  off_t offset, struct fuse_file_info *fi, int plus)
{
	struct lo_dirp *d = lo_dirp(fi);
	char *buf;
	char *p;
	size_t rem = 0;
	int err;

	(void) ino;

	buf = calloc(size, 1);
	if (!buf) {
		err = ENOMEM;
		goto error;
	}

	if (offset != d->offset) {
		seekdir(d->dp, offset);
		d->entry = NULL;
		d->offset = offset;
	}
	p = buf;
	rem = size;
	while (1) {
		size_t entsize;
		off_t nextoff;

		if (!d->entry) {
			errno = 0;
			d->entry = readdir(d->dp);
			if (!d->entry) {
				if(errno) {
					err = errno;
					goto error;
				}
				break;
			}
		}
		nextoff = telldir(d->dp);

		/* We don't return the information for "." or "..".  In particular,
		 * we need to make sure we don't increment the nlookup value for
		 * ".", because that will throw off the nlookup count when our
		 * FORGET method checks to see if it can free the inode. */
		if((strcmp(d->entry->d_name, ".") == 0) || (strcmp(d->entry->d_name, "..") == 0)) {
			entsize = 0;
		}

		else if (plus) {
			struct fuse_entry_param e;

			err = lo_do_lookup(req, ino, d->entry->d_name, &e);
			if (err)
				goto error;

			entsize = fuse_add_direntry_plus(req, p, rem,
							 d->entry->d_name,
							 &e, nextoff);

			/* If the new entry won't fit into this READDIR buffer,
			 * then decrement the nlookup count so we don't
			 * artificially inflate it. */
			if(entsize > rem) {
				struct lo_inode *i = lo_find(lo_data(req), &e.attr);
				i->nlookup--;
			}

		} else {
			struct stat st = {
				.st_ino = d->entry->d_ino,
				.st_mode = d->entry->d_type << 12,
			};
			entsize = fuse_add_direntry(req, p, rem,
						    d->entry->d_name,
						    &st, nextoff);
		}
		if(entsize > rem)
			break;

		p += entsize;
		rem -= entsize;

		d->entry = NULL;
		d->offset = nextoff;
	}

	err = 0;

error:
	/* According to libfuse latest documentation, only signal error if we
	 * haven't stored any entries yet otherwise we'd end up with wrong lookup
	 * counts for the entries that are already in the buffer.  So we return
	 * what we've collected until that point. */

	if(err && rem == size) {
		fuse_reply_err(req, err);
	}
	else {
		fuse_reply_buf(req, buf, size - rem);
	}

	free(buf);
}

/* Called from several functions:
 *    symlink - S_IFLNK(mode) = Symbolic link.
 *
 *    mknod   - S_IFDIR(mode) = Directory.
 *              S_IFLNK(mode) = Hard link.
 *              S_IFREG(mode) = Regular file.
 */
static void lo_mknod_symlink(fuse_req_t req, fuse_ino_t parent,
                             const char *name, mode_t mode, dev_t rdev,
                             const char *link)
{
	int newfd = -1;
	int res;
	int saverr = ENOMEM;
	struct lo_inode *dir = lo_inode(req, parent);
	int dirFD = dir->fd;

	do {
		struct lo_inode *inode = calloc(1, sizeof(struct lo_inode));
		if(inode == NULL) {
			LOG_ERROR(req, "Unable to allocate inode.");
			break;
		}

		if(S_ISLNK(mode)) {
			if((res = symlinkat(link, dirFD, name)) == -1) {
				saverr = errno;
				LOG_ERROR(req, "symlinkat(%s, %d, %s) failed (%m).",
				          link, dirFD, name);
				errno = saverr;
				break;
			}
		}

		else if(S_ISREG(mode)) {
			if((res = openat(dirFD, name, mode | O_CREAT, rdev)) == -1) {
				saverr = errno;
				LOG_ERROR(req, "openat(%d, %s, %o, %d) failed (%m).",
				          dirFD, name, mode, rdev);
				errno = saverr;
				break;
			}
		}

		else {
			if((res = mknodat(dirFD, name, mode, rdev)) == -1) {
				saverr = errno;
				LOG_ERROR(req, "mknodat(%d, %s, %o, %d) failed (%m).",
				          dirFD, name, mode, rdev);
				errno = saverr;
				break;
			}
		}

		const struct fuse_ctx *ctx = fuse_req_ctx(req);

		if(fchown(res, ctx->uid, ctx->gid) != 0) {
			saverr = errno;
			LOG_ERROR(req, "fchown(%d, %d, %d, 0) failed (%m).",
			          res, ctx->uid, ctx->gid);
			errno = saverr;
			break;
		}

		if(fchmod(res, mode) == -1) {
			saverr = errno;
			LOG_ERROR(req, "fchmod(%d, %o) failed (%m).", res, mode);
			break;
		}

		struct fuse_entry_param e;
		saverr = lo_do_lookup(req, parent, name, &e);
		if(saverr != 0) {
			LOG_ERROR(req, "lo_do_lookup() failed.");
			break;
		}

		fuse_reply_entry(req, &e);

	} while(0);

	fuse_reply_err(req, errno);
}

static int utimensat_empty_nofollow(struct lo_inode *inode, struct timespec *tv)
{
	int res;

	do {
		if(inode->is_symlink) {
			res = utimensat(inode->fd, "", tv, AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW);
			if((res == -1) && (errno == EINVAL)) {
				LOG_ERROR(NULL, "utimensat(%d, ...) failed (%m).", inode->fd);
				errno = EPERM;
			}

			break;
		}

		char linkName[PROCFS_LINK_SZ];
		linkFromFD(inode->fd, linkName, sizeof(linkName));
		res = utimensat(AT_FDCWD, linkName, tv, 0);
		if(res == -1) {
			int saverr = errno;
			LOG_ERROR(NULL, "utimensat() failed (%m).");
			errno = saverr;
		}

	} while(0);

	return res;
}

static int linkat_empty_nofollow(struct lo_inode *inode, int dfd, const char *name)
{
	int res;
	do {
		if(inode->is_symlink) {
			res = linkat(inode->fd, "", dfd, name, AT_EMPTY_PATH);
			if((res == -1) && ((errno == ENOENT) || (errno == EINVAL))) {
				LOG_ERROR(NULL, "Can't hard-link a symlink.");
				errno = EPERM;
			}
			break;
		}

		char linkName[PROCFS_LINK_SZ];
		linkFromFD(inode->fd, linkName, sizeof(linkName));
		res = linkat(AT_FDCWD, linkName, dfd, name, AT_SYMLINK_FOLLOW);
		if(res == -1) {
			int saverr = errno;
			LOG_ERROR(NULL, "linkat() failed (%m).");
			errno = saverr;
			break;
		}

	} while(0);

	return res;
}

/* *****************************************************************************
 * THE EXPORTED API FUNCTIONS.
 * ****************************************************************************/

static void lo_init(void *userdata, struct fuse_conn_info *conn)
{
	(void) userdata, conn;
	LOG_ENTER(NULL, "userdata %p : conn %p..", userdata, conn);
}

static void lo_create(fuse_req_t req, fuse_ino_t parent, const char *name, mode_t mode, struct fuse_file_info *fi)
{
	const char *accessModeStr = "";
	if(logToSyslog) {
		accessModeStr = fuseAccessModeToString(fi->flags);
	}
	LOG_ENTER(req, "nodeid %lld : name %s : mode %o : flags %s.",
	          parent, name, mode, accessModeStr);

	struct fuse_entry_param e;
	int error = 0;

	do {
		int dirfd = lo_fd(req, parent);
		int openatFlags = (fi->flags | O_CREAT) & ~O_NOFOLLOW;
		int fd = openat(dirfd, name, openatFlags, mode);
		if(fd == -1) {
			error = errno;
			LOG_ERROR(req, "openat(%d, %s, %o, %o) failed (%m).",
			          dirfd, name, openatFlags, mode);
			break;
		}

		if(fchmod(fd, mode) == -1) {
			error = errno;
			LOG_ERROR(req, "fchmod(%d, %o) failed (%m).", fd, mode);
			break;
		}

		fi->fh = fd;

		error = lo_do_lookup(req, parent, name, &e);

	} while(0);

	if(error) {
		fuse_reply_err(req, error);
	}
	else {
		fuse_reply_create(req, &e, fi);
	}

	LOG_EXIT(req, "nodeid %lld : name %s : mode %o.", parent, name, mode);
}

/* Not tested.  The goal is to make this capability be "not supported".  But
 * I've never seen it get called, so I don't know if it's being treated as
 * "not supported" or not. */
static void lo_fallocate(fuse_req_t req, fuse_ino_t ino, int mode, off_t offset, off_t length, struct fuse_file_info *fi)
{
	(void) fi;
	LOG_ENTER(req, "nodeid %" PRIu64 " : mode %o : offset %ld : length %ld..", ino, mode, offset, length);
	fuse_reply_err(req, ENOSYS);
	LOG_EXIT(req, "nodeid %" PRIu64 " : mode %o : offset %ld : length %ld..", ino, mode, offset, length);
}

static void lo_forget(fuse_req_t req, fuse_ino_t ino, uint64_t nlookup)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ": nlookup %" PRIu64 ".", ino, nlookup);
	do {
		struct lo_inode *inode = lo_inode(req, ino);
		LOG_TRACE(req, "nodeid %llu : %llu - %llu = %llu.",
		          ino, inode->nlookup, nlookup, (inode->nlookup - nlookup));

		assert(inode->nlookup >= nlookup);
		inode->nlookup -= nlookup;

		if(!inode->nlookup) {
			LOG_TRACE(req, "Freeing %" PRIu64 " : fd %d.", inode, inode->fd);
			lo_free(inode);
		}

		fuse_reply_none(req);
	} while(0);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

#undef DO_FORGET_MULTI
#ifdef DO_FORGET_MULTI
static void lo_forget_multi(fuse_req_t req, size_t count, struct fuse_forget_data *forgets)
{
	(void) req, count, forgets;
	LOG_ENTER(req, "count %ld : forgets %p.", count, forgets);
	int i;
	for(i = 0; i < count; i++) {
		struct fuse_forget_data *f = &forgets[i];
		fuse_ino_t ino     = f->ino;
		uint64_t   nlookup = f->nlookup;
		lo_forget(req, ino, nlookup);
	}
	LOG_EXIT(req, "count %ld : forgets %p.", count, forgets);
}
#endif // DO_FORGET_MULTI

static void lo_fsync(fuse_req_t req, fuse_ino_t ino, int datasync, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %lld : datasync %d.", ino, datasync);

	int res;
	if(datasync) {
		res = fdatasync(fi->fh);
	}
	else {
		res = fsync(fi->fh);
	}
	fuse_reply_err(req, res == -1 ? errno : 0);

	LOG_EXIT(req, "nodeid %lld : datasync %d : res %d (%m).", ino, datasync, res);
}

static void lo_getattr(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi)
{
	(void) fi;

	LOG_ENTER(req, "nodeid %lld.", ino);

	struct stat buf;
	int fd = lo_fd(req, ino);
	if(fstatat(fd, "", &buf, AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW) == -1) {
		int error = errno;
		LOG_TRACE(req, "fstatat(%d) failed (%m).", fd);
		fuse_reply_err(req, error);
	}
	else {
		LOG_TRACE(req, "dev/ino %d/%d : uid/gid %d/%d : %s : size %lld.",
		          buf.st_dev, buf.st_ino, buf.st_uid, buf.st_gid,
		          modeToString(buf.st_mode), buf.st_size);
		fuse_reply_attr(req, &buf, 0);
	}

	LOG_EXIT(req, "nodeid %lld.", ino);
}

#undef DO_GETXATTR
#ifdef DO_GETXATTR
static void lo_getxattr(fuse_req_t req, fuse_ino_t ino, const char *name, size_t size)
{
	LOG_ENTER(req, "nodeid %" PRIu64 " : name %s : size %ld.", ino, name, size);

	char *buf = NULL;
	int rc = 0;
	int error = 0;

	do {
		int fd = lo_fd(req, ino);

		/* If we want to read the data, allocate a buffer. */
		if(size > 0) {
			if((buf = (char *) malloc(size)) == NULL) {
				LOG_ERROR(req, "malloc(%d) failed (%m).", size);
				error = ERANGE;
				break;
			}
		}

		char pathName[PATH_MAX + 1];
		if(pathFromFD(fd, pathName, sizeof(pathName)) == -1) {
			LOG_ERROR(req, "malloc(%d) failed (%m).", size);
			error = ERANGE;
			break;
		}

		rc = getxattr(pathName, name, buf, size);
		error = errno;
		LOG_TRACE(req, "getxattr(%s, %s, %p, %ld) returned %d (%m).",
		          pathName, name, buf, size, rc);
		if(rc == -1) {
			/* The call failed.  This might be due to the buffer being too
			 * small (ERANGE). */
			break;
		}
	} while(0);

	if(error != 0) {
		fuse_reply_err(req, error);
	}
	else if(size == 0) {
		fuse_reply_xattr(req, rc);
	}
	else {
		fuse_reply_buf(req, buf, rc);
	}

	if(buf != NULL) {
		free(buf);
	}
	LOG_EXIT(req, "nodeid %" PRIu64 " : name %s : size %ld.", ino, name, size);
}
#endif // DO_GETXATTR

static void lo_link(fuse_req_t req, fuse_ino_t oldIno, fuse_ino_t newParentIno, const char *newPath)
{
	LOG_ENTER(req, "inode %" PRIu64 " --> NewParent %" PRIu64 ": newPath %s", oldIno, newParentIno, newPath);
	int res;
	struct lo_data *lo = lo_data(req);
	struct lo_inode *inode = lo_inode(req, oldIno);
	struct fuse_entry_param entry;
	int saverr;

	memset(&entry, 0, sizeof(entry));
	entry.attr_timeout = 1;
	entry.entry_timeout = 1;

	do {
		res = linkat_empty_nofollow(inode, lo_fd(req, newParentIno), newPath);
		if(res == -1) {
			saverr = errno;
			LOG_ERROR(req, "linkat_empty_nofollow() failed.");
			errno = saverr;
			break;
		}

#if 0
		res = fstatat(inode->fd, "", &entry.attr, AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW);
		if(res == -1) {
			saverr = errno;
			LOG_ERROR(req, "fstatat() failed (%m).");
			errno = saverr;
			break;
		}

		entry.ino = (fuse_ino_t) inode;
#endif

		lo_do_lookup(req, newParentIno, newPath, &entry);

	} while(0);

	if(res == -1) {
		fuse_reply_err(req, saverr);
	}
	else {
		fuse_reply_entry(req, &entry);
	}

	LOG_EXIT(req, "inode %" PRIu64 " --> NewParent %" PRIu64 ": newPath %s", oldIno, newParentIno, newPath);
}

static void lo_lookup(fuse_req_t req, fuse_ino_t parent, const char *name)
{
	LOG_ENTER(req, "parent %lld: name %s", parent, name);
	do {
		struct fuse_entry_param e;
		int err = lo_do_lookup(req, parent, name, &e);
		if (err)
			fuse_reply_err(req, err);
		else
			fuse_reply_entry(req, &e);
	} while(0);
	LOG_EXIT(req, "parent %lld: name %s", parent, name);
}

static void lo_mkdir(fuse_req_t req, fuse_ino_t parent, const char *name, mode_t mode)
{
	LOG_ENTER(req, "parent %" PRIu64 ": name %s : mode %o", parent, name, mode);
	int res;
	int saverr;
	struct fuse_entry_param e;

	do {
		const struct fuse_ctx *ctx = fuse_req_ctx(req);
		LOG_TRACE(req, "CTX: UID %d : GID %d : PID %d : UMASK %o.",
		          ctx->uid, ctx->gid, ctx->pid, ctx->umask);

		struct lo_inode *dir = lo_inode(req, parent);
		if((res = mkdirat(dir->fd, name, mode)) == -1) {
			saverr = errno;
			LOG_ERROR(req, "mkdirat(%d, %s, %o) failed (%m).", dir->fd, name, mode);
			break;
		}

		saverr = lo_do_lookup(req, parent, name, &e);
		if(saverr != 0) {
			LOG_ERROR(req, "lo_do_lookup() failed.");
			res = -1;
			break;
		}

		struct lo_inode *inode = lo_inode(req, e.ino);

		char pathName[PATH_MAX + 1];
		if(pathFromFD(inode->fd, pathName, sizeof(pathName)) == -1) {
			saverr = errno;
			LOG_ERROR(req, "Unable to read full directory name.");
			res = -1;
			break;
		}

		if((res = chown(pathName, ctx->uid, ctx->gid)) == -1) {
			saverr = errno;
			LOG_ERROR(req, "chown(%s, %d, %d) failed (%m).", pathName, ctx->uid, ctx->gid);
			break;
		}

		if((res = chmod(pathName, mode)) == -1) {
			saverr = errno;
			LOG_ERROR(req, "chmod(%s, %o) failed (%m).", pathName, mode);
			break;
		}
	} while(0);

	if(res == 0) {
		fuse_reply_entry(req, &e);
	}
	else {
		fuse_reply_err(req, saverr);
	}

	LOG_EXIT(req, "parent %" PRIu64 ": name %s : mode %o", parent, name, mode);
}

static void lo_mknod(fuse_req_t req, fuse_ino_t parent, const char *name, mode_t mode, dev_t rdev)
{
	LOG_ENTER(req, "parent %lld: name %s : mode %o (%s ) : rdev %d.",
	          parent, name, mode, modeToString(mode), rdev);
	lo_mknod_symlink(req, parent, name, mode, rdev, NULL);
	LOG_EXIT(req, "parent %" PRIu64 ": name %s : mode %o : rdev %d.", parent, name, mode, rdev);
}

static void lo_open(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi)
{
	int fd = -1;
	LOG_ENTER(req, "nodeid %lld.", ino);
	do {
		int linkFD = lo_fd(req, ino);

		char pathName[PATH_MAX + 1];
		if(pathFromFD(linkFD, pathName, sizeof(pathName)) == -1) {
			LOG_ERROR(req, "Unable to convert fd %d into a pathName.", fd);
			break;
		}

		int flags = fi->flags & ~O_NOFOLLOW;
		fd = open(pathName, flags);
		if(fd == -1) {
			int error = errno;
			LOG_TRACE(req, "open(%s, %o) failed (%m).", pathName, flags);
			errno = error;
			break;
		}
		else {
			LOG_TRACE(req, "open(%s, %o) returned %d.", pathName, flags, fd);
		}

		fi->fh = fd;
	} while(0);

	if(fd == -1) {
		fuse_reply_err(req, errno);
	}
	else {
		fuse_reply_open(req, fi);
	}

	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_opendir(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi)
{
	int error = 0;
	struct lo_dirp *d = NULL;

	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	do {
		d = calloc(1, sizeof(struct lo_dirp));
		if (d == NULL) {
			error = ENOMEM;
			LOG_ERROR(req, "calloc() failed (%m).");
			break;
		}

		d->fd = openat(lo_fd(req, ino), ".", O_RDONLY);
		if (d->fd == -1) {
			error = errno;
			LOG_ERROR(req, "openat(%d) failed. (%m).", lo_fd(req, ino));
			break;
		}

		d->dp = fdopendir(d->fd);
		if (d->dp == NULL) {
			error = errno;
			LOG_ERROR(req, "fdopendir(%d) failed. (%m).", d->fd);
			break;
		}

	} while(0);

	/* Clean up if we failed. */
	if(error) {
		if (d) {
			if (d->fd != -1)
				close(d->fd);
			free(d);
		}
		fuse_reply_err(req, error);
	}

	else {
		d->offset = 0;
		d->entry = NULL;

		fi->fh = (uintptr_t) d;
		fuse_reply_open(req, fi);
	}

	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_read(fuse_req_t req, fuse_ino_t ino, size_t size, off_t offset, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	struct fuse_bufvec buf = FUSE_BUFVEC_INIT(size);

	buf.buf[0].flags = FUSE_BUF_IS_FD | FUSE_BUF_FD_SEEK;
	buf.buf[0].fd = fi->fh;
	buf.buf[0].pos = offset;

	fuse_reply_data(req, &buf, FUSE_BUF_SPLICE_MOVE);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_readdir(fuse_req_t req, fuse_ino_t ino, size_t size, off_t offset, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	lo_do_readdir(req, ino, size, offset, fi, 0);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_readdirplus(fuse_req_t req, fuse_ino_t ino, size_t size, off_t offset, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	lo_do_readdir(req, ino, size, offset, fi, 1);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_readlink(fuse_req_t req, fuse_ino_t ino)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	do {
		char buf[PATH_MAX + 1];
		int res = readlinkat(lo_fd(req, ino), "", buf, sizeof(buf));
		if (res == -1) {
			fuse_reply_err(req, errno);
			break;
		}

		if (res == sizeof(buf)) {
			fuse_reply_err(req, ENAMETOOLONG);
			break;
		}

		buf[res] = '\0';
		fuse_reply_readlink(req, buf);
	} while(0);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_release(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	LOG_TRACE(req, "Closing %" PRIu64 " : fd %d.", ino, fi->fh);
	close(fi->fh);
	fuse_reply_err(req, 0);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_releasedir(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	struct lo_dirp *d = lo_dirp(fi);
	closedir(d->dp);
	free(d);
	fuse_reply_err(req, 0);
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_removexattr(fuse_req_t req, fuse_ino_t ino, const char *name)
{
	LOG_ENTER(req, "inode %" PRIu64 ": name %s", ino, name);
	int saverr;

	do {
		struct lo_inode *inode = lo_inode(req, ino);
		if(inode->is_symlink) {
			LOG_TRACE(req, "Can't removexattr on a symlink.");
			saverr = EPERM;
			break;
		}

		char linkName[PROCFS_LINK_SZ];
		linkFromFD(inode->fd, linkName, sizeof(linkName));
		int ret = removexattr(linkName, name);
		saverr = (ret == -1) ? errno : 0;

	} while(0);

	fuse_reply_err(req, saverr);
	LOG_EXIT(req, "inode %" PRIu64 ": name %s", ino, name);
}

static void lo_rename(fuse_req_t req, fuse_ino_t oldParent, const char *oldName, fuse_ino_t newParent, const char *newName, unsigned int flags)
{
	LOG_ENTER(req, "oldParent %" PRIu64 ": oldName %s -> newParent %" PRIu64 ": newName %s",
	          oldParent, oldName, newParent, newName);

	int saverr;
	int res = -1;

	do {
		if(flags) {
			LOG_ERROR(req, "flags is not-zero (%d).", flags);
			saverr = EINVAL;
			break;
		}

		res = renameat(lo_fd(req, oldParent), oldName,
		               lo_fd(req, newParent), newName);
		if(res == -1) {
			saverr = errno;
			LOG_ERROR(req, "renameat() failed (%m).");
			break;
		}

	} while(0);

	fuse_reply_err(req, (res == -1) ? saverr : 0);

	LOG_EXIT(req, "oldParent %" PRIu64 ": oldName %s -> newParent %" PRIu64 ": newName %s",
	          oldParent, oldName, newParent, newName);
}

static void lo_rmdir(fuse_req_t req, fuse_ino_t parent, const char *name)
{
	LOG_ENTER(req, "parent %" PRIu64 ": name %s", parent, name);
	int res = unlinkat(lo_fd(req, parent), name, AT_REMOVEDIR);
	fuse_reply_err(req, res == -1 ? errno : 0);
	LOG_EXIT(req, "parent %" PRIu64 ": name %s", parent, name);
}

/* valid is the bitmask of attributes to be set. */
static void lo_setattr(fuse_req_t req, fuse_ino_t ino, struct stat *attr,
                       int valid, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "inode %" PRIu64 ".", ino);
	int saverr;
	struct lo_inode *inode = lo_inode(req, ino);
	int ifd = inode->fd;
	int res;

	do {
		if(valid & FUSE_SET_ATTR_MODE) {
			if(fi) {
				res = fchmod(fi->fh, attr->st_mode);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "fchmod(%d, %o) failed (%m).",
					          fi->fh, attr->st_mode);
					break;
				}
			}
			else {
				char linkName[PROCFS_LINK_SZ];
				linkFromFD(ifd, linkName, sizeof(linkName));
				res = chmod(linkName, attr->st_mode);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "chmod(%s, %o) failed (%m).",
					          linkName, attr->st_mode);
					break;
				}
			}
		}

		if(valid & FUSE_SET_ATTR_SIZE) {
			if(fi) {
				res = ftruncate(fi->fh, attr->st_size);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "ftruncate(%d, %d) failed (%m).",
					          fi->fh, attr->st_size);
					break;
				}
			}
			else {
				char linkName[PROCFS_LINK_SZ];
				linkFromFD(ifd, linkName, sizeof(linkName));
				res = truncate(linkName, attr->st_size);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "truncate(%s, %d) failed (%m).",
					          linkName, attr->st_size);
					break;
				}
			}
		}

		if(valid & (FUSE_SET_ATTR_ATIME | FUSE_SET_ATTR_MTIME)) {
			struct timespec tv[2];
			tv[0].tv_sec = 0;
			tv[1].tv_sec = 0;
			tv[0].tv_nsec = UTIME_OMIT;
			tv[1].tv_nsec = UTIME_OMIT;

			if(valid & FUSE_SET_ATTR_ATIME_NOW) {
				tv[0].tv_nsec = UTIME_NOW;
			}
			else if(valid & FUSE_SET_ATTR_ATIME) {
				tv[0] = attr->st_atim;
			}

			if(valid & FUSE_SET_ATTR_MTIME_NOW) {
				tv[1].tv_nsec = UTIME_NOW;
			}
			else if (valid & FUSE_SET_ATTR_MTIME) {
				tv[1] = attr->st_mtim;
			}

			if(fi) {
				res = futimens(fi->fh, tv);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "futimens(%d, ...) failed {%m).", fi->fh);
					break;
				}
			}
			else {
				res = utimensat_empty_nofollow(inode, tv);
				if(res == -1) {
					saverr = errno;
					LOG_ERROR(req, "utimensat_empty_nofollow() failed. (%m)");
					break;
				}
			}
		}
	} while(0);

	if(res == -1) {
		fuse_reply_err(req, saverr);
	}
	else {
		return lo_getattr(req, ino, fi);
	}

	LOG_EXIT(req, "inode %" PRIu64 ".", ino);
}

static void lo_statfs(fuse_req_t req, fuse_ino_t ino)
{
	LOG_ENTER(req, "nodeid %" PRIu64 ".", ino);
	int fd = lo_fd(req, ino);
	struct statvfs stbuf;
	int rc = fstatvfs(fd, &stbuf);
	if(rc == 0) {
		LOG_TRACE(req, "fstatvfs(%d) succeeded: fsid %ld.", fd, stbuf.f_fsid);
		fuse_reply_statfs(req, &stbuf);
	}
	else {
		LOG_TRACE(req, "fstatvfs(%d) failed (%m).", fd);
		fuse_reply_err(req, errno);
	}
	LOG_EXIT(req, "nodeid %" PRIu64 ".", ino);
}

static void lo_symlink(fuse_req_t req, const char *link, fuse_ino_t parent, const char *name)
{
	LOG_ENTER(req, "parent %" PRIu64 " : name %s -> %s.", parent, name, link);
	lo_mknod_symlink(req, parent, name, S_IFLNK, 0, link);
	LOG_EXIT(req, "parent %" PRIu64 " : name %s -> %s.", parent, name, link);
}

static void lo_write_buf(fuse_req_t req, fuse_ino_t ino, struct fuse_bufvec *bufv, off_t off, struct fuse_file_info *fi)
{
	LOG_ENTER(req, "nodeid %lld : off %ld.", ino, off);

	struct fuse_bufvec outBuf = FUSE_BUFVEC_INIT(fuse_buf_size(bufv));
	outBuf.buf[0].flags = FUSE_BUF_IS_FD | FUSE_BUF_FD_SEEK;
	outBuf.buf[0].fd = fi->fh;
	outBuf.buf[0].pos = off;

	ssize_t res = fuse_buf_copy(&outBuf, bufv, 0);
	if(res < 0) {
		fuse_reply_err(req, -res);
	}
	else {
		fuse_reply_write(req, (size_t) res);
	}

	LOG_EXIT(req, "nodeid %lld : off %ld : res %d.", ino, off, res);
}

static void lo_unlink(fuse_req_t req, fuse_ino_t parent, const char *name)
{
	LOG_ENTER(req, "nodeid %" PRIu64 " : name %s", parent, name);
	int res = unlinkat(lo_fd(req, parent), name, 0);
	fuse_reply_err(req, res == -1 ? errno : 0);
	LOG_EXIT(req, "nodeid %" PRIu64 " : name %s", parent, name);
}

/* *****************************************************************************
 * STUBS.  IF YOU NEED ONE OF THESE FUNCTIONS, THEN MOVE IT UP ABOVE THIS
 * COMMENT AND IMPLEMENT IT.  THE LISTS ARE IN ALPHABETICAL ORDER.  KEEP THEM
 * THAT WAY!!!!!
 * ****************************************************************************/

#undef DO_UNIMPLEMENTED_FUNCS
#ifdef DO_UNIMPLEMENTED_FUNCS
static void lo_access(fuse_req_t req, fuse_ino_t ino, int mask) { (void) req, ino, mask; assert(0); }
static void lo_bmap(fuse_req_t req, fuse_ino_t ino, size_t blocksize, uint64_t idx) { (void) req, ino, blocksize, idx; assert(0); }
static void lo_destroy(void *userdata) { (void) userdata; assert(0); }
static void lo_flock(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi, int op) { (void) req, ino, fi, op; assert(0); }
static void lo_flush(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi) { (void) req, ino, fi; assert(0); }
static void lo_fsyncdir(fuse_req_t req, fuse_ino_t ino, int datasync, struct fuse_file_info *fi) { (void) req, ino, datasync, fi; assert(0); }
static void lo_getlk(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi, struct flock *lock) { (void) req, ino, fi, lock; assert(0); }
static void lo_ioctl(fuse_req_t req, fuse_ino_t ino, int cmd, void *arg, struct fuse_file_info *fi, unsigned flags, const void *in_buf, size_t in_bufsz, size_t out_bufsz) { (void) req, ino, cmd, arg, fi, flags, in_buf, in_bufsz, out_bufsz; assert(0); }
static void lo_listxattr(fuse_req_t req, fuse_ino_t ino, size_t size) { (void) req, ino, size; assert(0); }
static void lo_poll(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi, struct fuse_pollhandle *ph) { (void) req, ino, fi, ph; assert(0); }
static void lo_retrieve_reply(fuse_req_t req, void *cookie, fuse_ino_t ino, off_t offset, struct fuse_bufvec *bufv) { (void) req, cookie, ino, offset, bufv; assert(0); }
static void lo_setlk(fuse_req_t req, fuse_ino_t ino, struct fuse_file_info *fi, struct flock *lock, int sleep) { (void) req, ino, fi, lock, sleep; assert(0); }
static void lo_setxattr(fuse_req_t req, fuse_ino_t ino, const char *name, const char *value, size_t size, int flags) { (void) req, ino, name, value, size, flags; assert(0); }
static void lo_write(fuse_req_t req, fuse_ino_t ino, const char *buf, size_t size, off_t off, struct fuse_file_info *fi) { (void) req, ino, buf, size, off, fi; assert(0); }
#endif /* DO_UNIMPLEMENTED_FUNCS */

static struct fuse_lowlevel_ops lo_oper = {
	.init		= lo_init, 
	.create		= lo_create,
	.fallocate	= lo_fallocate,
	.forget		= lo_forget,
#ifdef DO_FORGET_MULTI
	.forget_multi	= lo_forget_multi,
#endif // DO_FORGET_MULTI
	.fsync		= lo_fsync,
	.getattr	= lo_getattr,
#ifdef DO_GETXATTR
	.getxattr	= lo_getxattr,
#endif // DO_GETXATTR
	.link		= lo_link,
	.lookup		= lo_lookup,
	.mkdir		= lo_mkdir,
	.mknod		= lo_mknod,
	.open		= lo_open,
	.opendir	= lo_opendir,
	.read		= lo_read,
	.readdir	= lo_readdir,
	.readdirplus	= lo_readdirplus,
	.readlink	= lo_readlink,
	.release	= lo_release,
	.releasedir	= lo_releasedir,
	.removexattr	= lo_removexattr,
	.rename		= lo_rename,
	.rmdir		= lo_rmdir,
	.setattr	= lo_setattr,
	.statfs		= lo_statfs,
	.symlink	= lo_symlink,
	.unlink		= lo_unlink,
	.write_buf	= lo_write_buf,
#ifdef DO_UNIMPLEMENTED_FUNCS
	.access		= lo_access,
	.bmap		= lo_bmap,
	.destroy	= lo_destroy,
	.flock		= lo_flock,
	.flush		= lo_flush,
	.fsyncdir	= lo_fsyncdir,
	.getlk		= lo_getlk,
	.ioctl		= lo_ioctl,
	.listxattr	= lo_listxattr,
	.poll		= lo_poll,
	.retrieve_reply	= lo_retrieve_reply,
	.setlk		= lo_setlk,
	.setxattr	= lo_setxattr,
	.write		= lo_write,
#endif /* DO_UNIMPLEMENTED_FUNCS */
};

int main(int argc, char *argv[])
{
	struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
	struct fuse_session *se;
	struct fuse_cmdline_opts opts;
	struct lo_data lo = { .debug = 0 };
	int ret = -1;

	lo.root.next = lo.root.prev = &lo.root;
	lo.root.fd = -1;

	if (fuse_parse_cmdline(&args, &opts) != 0)
		return 1;
	if (opts.show_help) {
		printf("usage: %s [options] <mountpoint>\n\n", argv[0]);
		fuse_cmdline_help();
		fuse_lowlevel_help();
		ret = 0;
		goto err_out1;
	} else if (opts.show_version) {
		printf("FUSE library version %s\n", fuse_pkgversion());
		fuse_lowlevel_version();
		ret = 0;
		goto err_out1;
	}

	/* Get the name of the directory that we're going to bridge to. */
	char *dstMntPnt = getenv("PROXY_BRIDGE_DST");
	printf("dstMntPnt = >%s<.\n", dstMntPnt);

	lo.debug = opts.debug;
	lo.root.is_symlink = false;
	lo.root.fd = open(dstMntPnt, O_PATH);
	lo.root.nlookup = 2;
	if (lo.root.fd == -1)
		err(1, "open(\"%s\", O_PATH)", dstMntPnt);

	se = fuse_session_new(&args, &lo_oper, sizeof(lo_oper), &lo);
	if (se == NULL)
	    goto err_out1;

	if (fuse_set_signal_handlers(se) != 0)
	    goto err_out2;

	if (fuse_session_mount(se, opts.mountpoint) != 0)
	    goto err_out3;

	fuse_daemonize(opts.foreground);

	/* Block until ctrl+c or fusermount -u */
	if (opts.singlethread)
		ret = fuse_session_loop(se);
	else
		ret = fuse_session_loop_mt(se, opts.clone_fd);

	fuse_session_unmount(se);
err_out3:
	fuse_remove_signal_handlers(se);
err_out2:
	fuse_session_destroy(se);
err_out1:
	free(opts.mountpoint);
	fuse_opt_free_args(&args);

	while (lo.root.next != &lo.root)
		lo_free(lo.root.next);
	if (lo.root.fd >= 0)
		close(lo.root.fd);

	return ret ? 1 : 0;
}
