

packageversion:=$(shell cat mospack/DESCRIPTION | egrep Version | sed 's/Version://g')

package: SHELL:=/bin/bash
package: mospack
	R CMD build mospack
	R CMD INSTALL mospack_$(shell printf "%s"${packageversion}).tar.gz

readme: README.md
	pandoc README.md -o README.pdf
