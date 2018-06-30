.include <src.opts.mk>
.include <bsd.arch.inc.mk>

.if make(check-optional) || make(check-optional-dirs) || \
    make(delete-optional) || make(delete-optional-dirs)

.include "OptionalDirs.inc"

delete-optional-dirs:
	@echo ">>> Removing optional directories"
	@${MAKE} -f ${.CURDIR}/Makefile ${.MAKEFLAGS} ${.TARGET} \
	    -V OPTIONAL_DIRS | xargs -n1 | \
	while read dir; do \
		if [ -d "${DESTDIR}/$${dir}" ]; then \
			rmdir -v "${DESTDIR}/$${dir}"; \
		fi; \
	done
	@echo ">>> Optional directories removed"

check-optional-dirs:
	@echo ">>> Checking for optional directories"
	@${MAKE} -f ${.CURDIR}/Makefile ${.MAKEFLAGS} ${.TARGET} \
	    -V OPTIONAL_DIRS | xargs -n1 | \
	while read dir; do \
		if [ -d "${DESTDIR}/$${dir}" ]; then \
			echo "${DESTDIR}/$${dir}"; \
		fi; \
	done
	@echo ">>> Optional dirs checked"

delete-optional: delete-optional-dirs

check-optional: check-optional-dirs

.endif
