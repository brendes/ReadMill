# Copyright (c) 2010-2011 Genome Research Ltd. All rights reserved.
#
# This file is part of readmill.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PHONY:	all libs clean

all: libs
	sbcl --dynamic-space-size 1024 --no-userinit --disable-debugger --load build.lisp

libs:
	git submodule update --init --recursive

clean:
	rm -r build/*
