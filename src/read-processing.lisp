;;;
;;; Copyright (c) 2010-2011 Genome Research Ltd. All rights reserved.
;;;
;;; This file is part of readmill.
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;;

(in-package :uk.ac.sanger.readmill)

(defun split-bam-by-size (argv input output-name
                          &key (separator ".part.") (max-size 1000000))
  "Creates a number of BAM files from BAM file INPUT, each containing
up to MAX-SIZE reads. The output files are named
<OUTPUT-NAME><SEPARATOR><integer>.bam with sequential numbering,
staring from 0. Returns two values; a list of names of the new files
and a list of the numbers of reads in each."
  (check-arguments (stringp separator) (separator) "expected a string")
  (check-arguments (and (integerp max-size) (plusp max-size)) (max-size)
                   "expected a positive integer")
  (let ((file-namer (pathname-extender (pathname output-name)
                                       :separator separator :type "bam")))
    (with-bam (in (header num-refs ref-meta) input)
      (let ((hd (add-readmill-pg (make-sam-header header) argv)))
        (loop
           for part = (funcall file-namer)
           for n = (write-n-reads in max-size part
                                  (header-string hd) num-refs ref-meta)
           until (zerop n)
           collect part into parts
           collect n into counts
           finally (return (values parts counts)))))))

(defun write-n-reads (in n pathname header num-refs ref-meta)
  "Writes up to N reads taken from generator in to a new BAM file at
PATHNAME, having BAM metadata HEADER, NUM-REFS and REF-META."
  (declare (optimize (speed 3)))
  (if (not (has-more-p in))
      0
      (with-bam (out (header num-refs ref-meta) pathname :direction :output
                     :if-exists :supersede :if-does-not-exist :create)
        (loop
           for count of-type fixnum from 0 below n
           while (has-more-p in)
           do (consume out (next in))
           finally (return count)))))

(defun quality-trim-position (aln quality-threshold &key (start 0) end)
  "Calculates the position at which a read should be trimmed using
BWA's 3-prime trimming algorithm, which maximises the sum of
differences between QUALITY-THRESHOLD and each base quality, starting
from END and proceeding to START. Returns two values, the position
after the most 3-prime base to retain and the maximized sum of
differences."
  (let* ((len (read-length aln))
         (end (or end (1- len)))
         (qualities (map-into (make-array len
                                          :element-type 'quality-score
                                          :initial-element 0)
                              #'decode-phred-quality (quality-string aln))))
    (do ((i end (1- i))
         (j end)
         (score 0)
         (max-score 0))
        ((or (< i start) (minusp score)) (values (1+ j) max-score))
      (incf score (- quality-threshold (aref qualities i)))
      (when (> score max-score)
        (setf max-score score
              j i)))))
