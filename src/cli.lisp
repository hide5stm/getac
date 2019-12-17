(defpackage #:getac/cli
  (:use #:cl)
  (:export #:option
           #:defoption
           #:option-name
           #:option-handler
           #:find-option
           #:cli-error
           #:invalid-option
           #:missing-option-value
           #:print-options-usage
           #:parse-argv))
(in-package #:getac/cli)

(define-condition cli-error (error) ())
(define-condition invalid-option (cli-error)
  ((name :initarg :name))
  (:report (lambda (error stream)
             (format stream "Invalid option: ~A" (slot-value error 'name)))))
(define-condition missing-option-value (cli-error)
  ((name :initarg :name))
  (:report (lambda (error stream)
             (format stream "Missing value for the option: ~A" (slot-value error 'name)))))

(defvar *options* '())
(defvar *short-options* '())

(defstruct option
  name
  docstring
  short
  lambda-list
  handler)

(defmacro defoption (name (&key short) lambda-list &body body)
  (let ((option (gensym "OPTION"))
        (g-short (gensym "SHORT")))
    ;; Currently support only zero or one arguments
    (assert (or (null lambda-list)
                (null (rest lambda-list))))
    (multiple-value-bind (docstring body)
        (if (and (rest body)
                 (stringp (first body)))
            (values (first body) (rest body))
            (values nil body))
      `(let* ((,g-short ,short)
              (,option (make-option :name ,name
                                    :docstring ,docstring
                                    :short ,g-short
                                    :lambda-list ',lambda-list
                                    :handler (lambda ,lambda-list ,@body))))
         (push (cons (format nil "--~A" ,name) ,option) *options*)
         (when ,g-short
           (push (cons (format nil "-~A" ,g-short) ,option) *short-options*))
         ,option))))

(defun find-option (name &optional errorp)
  (let ((option (or (cdr (assoc name *options* :test 'equal))
                    (cdr (assoc name *short-options* :test 'equal)))))
    (when (and (null option)
               errorp)
      (error 'invalid-option :name name))
    option))

(defun print-usage-of-option (option stream)
  (format stream "~&    ~@[-~A, ~]--~A~@[=~{<~(~A~)>~^ ~}~]~%~@[        ~A~%~]"
          (option-short option)
          (option-name option)
          (option-lambda-list option)
          (option-docstring option)))

(defun print-options-usage (&optional (stream *error-output*))
  (dolist (option (reverse *options*))
    (print-usage-of-option (cdr option) stream)))

(defun option-string-p (string)
  (and (stringp string)
       (<= 2 (length string))
       (char= #\- (aref string 0))))

(defun parse-argv (argv)
  (loop for arg = (pop argv)
        while arg
        if (option-string-p arg)
        append (let ((=-pos (position #\= arg :start 1)))
                 (multiple-value-bind (option-name value)
                     (if =-pos
                         (values (subseq arg 0 =-pos)
                                 (subseq arg (1+ =-pos)))
                         (values arg nil))
                   (let ((option (find-option option-name t)))
                     (when (and (option-lambda-list option)
                                (null value))
                       (setf value (pop argv))
                       (when (or (null value)
                                 (option-string-p value))
                         (error 'missing-option-value
                                :name option-name)))
                     (apply (option-handler option)
                            (and value (list value)))))) into results
        else
        do (return (values results (cons arg argv)))
        finally (return (values results nil))))
