(in-package #:org.shirakumo.random-state)

(declaim (inline fit-bits))
(declaim (ftype (function ((unsigned-byte 8) (integer 0)) (integer 0)) fit-bits))
(defun fit-bits (bits x)
  (logand x (1- (ash 1 bits))))

(define-compiler-macro fit-bits (&whole whole bits x &environment env)
  (if (constantp bits env)
      `(logand ,x (load-time-value (1- (ash 1 ,bits))))
      whole))

(defun byte-array-to-int (array)
  (loop with int = 0
        for i from 0 below (length array)
        do (setf (ldb (byte 8 (* i 8)) int) (aref array i))
        finally (return int)))

(defun hopefully-sufficiently-random-seed ()
  (or
   #+unix
   (ignore-errors
    (let ((seq (make-array 8 :element-type '(unsigned-byte 8))))
      (with-open-file (stream #P"/dev/urandom" :element-type '(unsigned-byte 8))
        (read-sequence seq stream))
      (byte-array-to-int seq)))
   #+(and win32 sb-dynamic-core)
   (ignore-errors
    (byte-array-to-int (sb-win32:crypt-gen-random 8)))
   (logxor #+sbcl (sb-ext:get-bytes-consed)
           (get-internal-real-time)
           (get-universal-time))))

(defun 32bit-seed-array (size seed)
  (declare (optimize speed))
  (let ((array (make-array size :element-type '(unsigned-byte 32))))
    (setf (aref array 0) (fit-bits 32 seed))
    ;; Using generator from:
    ;; Line 25 of Table 1 in "The Art of Computer Programming Vol. 2" (2nd Ed.), pp 102
    (loop for i from 1 below size
          do (setf (aref array i)
                   (fit-bits 32 (* 69069 (aref array (1- i))))))
    array))

(defun 64bit-seed-array (size seed)
  (declare (optimize speed))
  (let ((array (make-array size :element-type '(unsigned-byte 64))))
    (setf (aref array 0) (fit-bits 64 seed))
    (loop for i from 1 below size
          do (setf (aref array i)
                   (fit-bits 64 (+ (* 6364136223846793005
                                     (logxor (aref array (1- i))
                                             (ash (aref array (1- i)) -62)))
                                  i))))
    array))

(defun barr (bytes &rest contents)
  (make-array (length contents) :element-type `(unsigned-byte ,bytes) :initial-contents contents))

(defmacro incfmod (place mod &optional (delta 1))
  `(setf ,place (mod (+ ,place ,delta) ,mod)))

(defun intern* (&rest args)
  (intern (format NIL "~{~a~^-~}" (mapcar #'string args))))

(defmacro update (bits place op &rest args)
  `(setf ,place (fit-bits ,bits (,op ,place ,@args))))

(defmethod copy ((thing number))
  thing)

(defmethod copy ((thing array))
  (make-array (array-dimensions thing)
              :element-type (array-element-type thing)
              :fill-pointer (array-has-fill-pointer-p thing)
              :adjustable (adjustable-array-p thing)
              :initial-contents thing))

(defun histogram (samples bins)
  (let ((histogram (make-array bins))
        (sample-contribution (/ (length samples))))
    (loop for sample across samples
          do (incf (aref histogram (floor (* sample bins)))
                   sample-contribution))
    histogram))

(defun print-histogram (histogram &key (stream *standard-output*) (width 70))
  (let ((half-width (/ width 2))
        (total 0.0))
    (loop for bin across histogram
          for deviation = (* 100 (- bin (/ (length histogram))))
          for chars = (floor (* width deviation))
          do (format stream "~6,3@f% ~v@{░~}~v@{█~}~v@{░~}~%" deviation
                     (min half-width (- half-width chars))
                     (abs chars)
                     (min half-width (+ half-width chars))
                     NIL)
             (incf total (abs deviation)))
    (format stream "Cumulative deviation: ~6,3f%~%" total)))
