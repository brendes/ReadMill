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

(defun about (parsed-args &optional argv)
  "Reports information about the system and exits."
  (declare (ignore argv))
  (flet ((platform-info ()
           (format *standard-output* "Common Lisp ~a version ~s on ~a~%"
                   (lisp-implementation-type) (lisp-implementation-version)
                   (machine-type)))
         (version-info ()
           (format *standard-output* "ReadMill version ~s~%~%"
                   *readmill-version*)))
    (cond ((and (option-value 'platform parsed-args)
                (not (option-value 'version parsed-args)))
           (platform-info))
          ((and (option-value 'version parsed-args)
                (not (option-value 'platform parsed-args)))
           (version-info))
          (t
           (version-info)
           (platform-info)))))

(defun quality-plot (parsed-args &optional argv)
  "Plots the mean quality of bases at each position in the reads."
  (declare (ignore argv))
  (destructuring-bind (plot input read-group regions)
      (mapcar (lambda (option)
                (option-value option parsed-args))
              '(plot input read-group regions))
    (write-quality-plot plot input
                        :index (when regions
                                 (find-and-read-bam-index parsed-args))
                        :regions (mapcar #'parse-region-string regions)
                        :read-group read-group)))

(defun pattern-report (parsed-args &optional argv)
  (declare (ignore argv))
  "Reports the frequency of repeated patterns of specified bases."
  (destructuring-bind (report char min-freq input regions read-group)
      (mapcar (lambda (option)
                (option-value option parsed-args))
              '(report char min-freq input regions read-group))
    (write-pattern-report report char min-freq input
                          :index (when regions
                                   (find-and-read-bam-index parsed-args))
                          :regions (mapcar #'parse-region-string regions)
                          :read-group read-group)))

(defun read-filter (parsed-args &optional argv)
  "Filters BAM data, removing reads that match any of the filters."
  (let* ((input (option-value 'input parsed-args))
         (output (option-value 'output parsed-args))
         (filter-args '(read-group queries))
         (filters (remove-if #'null
                             (mapcan (lambda (arg)
                                       (make-filters arg parsed-args))
                                     filter-args)))
         (descriptors (remove-if #'null
                                 (mapcan (lambda (arg)
                                           (make-descriptors arg parsed-args))
                                         filter-args)))
         (orphans (option-value 'orphans parsed-args))
         (json-file (option-value 'json-file parsed-args nil)))
    (filter-bam argv input output filters descriptors
                :orphans orphans :json-file json-file)))

(defun split-bam (parsed-args &optional argv)
  "Splits BAM data into files that contain no more than a specified
maximum number of reads."
  (let ((input (option-value 'input parsed-args))
        (output (option-value 'output parsed-args))
        (separator (option-value 'separator parsed-args))
        (max-size (option-value 'max-size parsed-args)))
    (split-bam-by-size argv input output :separator separator
                       :max-size max-size)))

(defun find-and-read-bam-index (parsed-args)
  (let ((input (option-value 'input parsed-args))
        (index-file (option-value 'index parsed-args)))
    (check-readmill-arguments
     (not (streamp (maybe-standard-stream input))) (input)
     "a BAM index may not be used with ~a" input)
    (let ((index-file (or index-file (find-bam-index input))))
      (check-readmill-arguments
       index-file (input) "failed to infer a BAM index file for ~a" input)
      (with-open-file (stream index-file :element-type 'octet)
        (read-bam-index stream)))))

(defgeneric make-filters (arg parsed-args)
  (:documentation "Returns a list of filter predicates appropriate to
CLI argument ARG. The list may be empty, or contain a single element.")
  (:method (arg args)
    (declare (ignore args))
    nil)
  (:method ((arg (eql 'read-group)) args)
    (when (option-value 'read-group args nil)
      (list (complement (make-rg-p (option-value 'read-group args))))))
  (:method ((arg (eql 'min-quality)) args)
    (when (option-value 'min-quality args nil)
      (list (make-quality-p (option-value 'min-quality args)
                            :start (option-value 'read-start args 0)
                            :end (option-value 'read-end args nil)))))
  (:method ((arg (eql 'queries)) args)
    (when (option-value 'queries args nil)
      (let ((start (option-value 'start args 0))
            (end (option-value 'end args nil)))
        (mapcar (lambda (query)
                  (make-subseq-p query :start start :end end))
                (option-value 'queries args))))))

(defgeneric make-descriptors (arg parsed-args)
  (:documentation "Returns a list of filter descriptors appropriate to
CLI argument ARG. The list may be empty, or contain a single element.")
  (:method (arg args)
    (declare (ignore args))
    nil)
  (:method ((arg (eql 'read-group)) args)
    (when (option-value 'read-group args nil)
      (let ((msg (format nil "not in read-group ~s"
                         (option-value 'read-group args))))
        (list (lambda (calls true)
                (describe-filter-result calls true "read-group" msg))))))
  (:method ((arg (eql 'min-quality)) args)
    (when (option-value 'min-quality args nil)
      (let* ((start (option-value 'start args 0))
             (end (option-value 'end args nil))
             (min-quality (option-value 'min-quality args))
             (msg (format nil "a base between ~d and ~a has quality below ~d"
                          start (or end "the read end") min-quality)))
        (list (lambda (calls true)
                (describe-filter-result calls true "quality-filter" msg))))))
  (:method ((arg (eql 'queries)) args)
    (when (option-value 'queries args nil)
      (let* ((start (option-value 'start args 0))
             (end (option-value 'end args nil))
             (fmt (format nil "sequence ~~s found between ~d and ~a"
                          start (or end "the read end"))))
        (mapcar (lambda (query)
                  (lambda (calls true)
                    (describe-filter-result calls true "subseq-filter"
                                            (format nil fmt query))))
                (option-value 'queries args))))))
