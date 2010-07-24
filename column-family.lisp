;;; -*- Mode: lisp; Syntax: ansi-common-lisp; Base: 10; Package: de.setf.cassandra; -*-

(in-package :de.setf.cassandra)

;;;  This file defines column family operators for the 'de.setf.cassandra' library.
;;;  (c) 2010 james anderson
;;;
;;;  'de.setf.cassandra' is free software: you can redistribute it and/or modify
;;;  it under the terms of the GNU Lesser General Public License as published by
;;;  the Free Software Foundation, either version 3 of the License, or
;;;  (at your option) any later version.
;;;
;;;  'de.setf.cassandra' is distributed in the hope that it will be useful,
;;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;  GNU Lesser General Public License for more details.
;;;
;;;  You should have received a copy of the GNU Lesser General Public License along
;;;  with 'de.setf.cassandra' as 'lgpl.txt'. If not, see the GNU [site](http://www.gnu.org/licenses/). 

;;;
;;; interface

(defgeneric get-attribute (column-family key column-name)
  (:documentation "Given a COLUMN-FAMILY, KEY, and COLUMN-NAME, retrieve the designated attribute 'column'
 from the family's store. This returns the column struct, which comprises the name, value, and timestamp.
 A simple column-family requires atomic keys, while a super-column permits either the atomic family key or
 a list of family-key and super-column key."))


(defgeneric get-attribute-value (column-family key column-name)
  (:documentation "Given a COLUMN-FAMILY, KEY, and COLUMN-NAME, retrieve the designated attribute value
 from the family's store. This retrieves the attribute 'column' and returns just its value.")

  (:method (column-family key column-name)
    (cassandra::column-value (get-attribute column-family key column-name))))


(defgeneric set-attribute (column-family key column-name value &optional timestamp)
  (:documentation "Given a COLUMN-FAMILY, KEY, COLUMN-NAME, VALUE, and an optional TIMESTAMP, store the
 designated attribute 'column' in the family's store. The timestamp defaults to the UUID-V1 timestamp.
 A simple column-family requires atomic keys, while a super-column requires a list of family-key and
 super-column key.") )


(defgeneric get-attributes (column-family key &key start finish column-names reversed count)
  (:documentation "Given a COLUMN-FAMILY, KEY, and a combination of START and FINISH column names, a
 COLUMN-NAME list, REVERSED indicator, and a COUNT, retrieve the designated attribute 'columns' from the 
 family's store. (see cassandra:get-silce.) A simple column-family requires atomic an key, while a super-column
 permits either the atomic family key or a list of family-key and super-column key."))


(defgeneric get-attribute-values (column-family key &key start finish column-names reversed count)
  (:documentation "Given a COLUMN-FAMILY, a KEY, and constraints as for get-attributes, retrieve the
 attribute 'columns' and of those the respective values.")

  (:method (column-family key &rest args)
    (declare (dynamic-extent args))
    (mapcar #'cassandra::column-value (apply #'get-attributes column-family key args))))


(defgeneric set-attributes (column-family key &rest property-list)
  (:documentation "Given a COLUMN-FAMILY, a key, and a property list of column names and values,
 store the designated attribute 'columns' in the family's store. The first property can be :timestamp,
 to specify the column timestamp, for which the default is the UUID-V1 timestamp."))


;;;
;;; classes
;;;  abstract-column-famiy
;;;  column-family
;;;  super-column-family

(defclass abstract-column-family ()
  ((keyspace
    :initform (error "keyspace is required.") :initarg :keyspace
    :reader column-family-keyspace)
   (name
    :initform (error "name is required.") :initarg :name
    :accessor column-family-name)
   (slice-size
     :accessor column-family-slice-size
     :type i32)
   (columnpath
    :reader column-family-columnpath)
   (columnparent
    :reader column-family-columnparent)
   (slicepredicate
    :reader column-family-slicepredicate)
   (slicerange
    :reader column-family-slicerange)))


(defclass column-family (abstract-column-family)
  ())


(defclass super-column-family (abstract-column-family)
  ())


;;; generic operations

(defmethod initialize-instance :after ((instance abstract-column-family) &key
                                       (slice-size (keyspace-slice-size (column-family-keyspace instance))))
  (setf (slot-value instance 'columnpath)
        (cassandra::make-columnpath :column-family (column-family-name instance)))
  (setf (slot-value instance 'columnparent)
        (cassandra::make-columnparent :column-family (column-family-name instance)))
  (setf (slot-value instance 'slicepredicate)
        (cassandra::make-slicepredicate))
  (setf (slot-value instance 'slicerange)
        (cassandra::make-slicerange :reversed nil :count slice-size :start "" :finish ""))
  (setf (column-family-slice-size instance)
        slice-size))


;;;
;;; column family operators expect the column key to map to a sequence of columns.

(defmethod get-attribute ((column-family column-family) key column-name)
  (let ((column-path (column-family-columnpath column-family))
        (cosc nil))
    (setf (cassandra::columnpath-column column-path) column-name)
    (when (setf cosc (get (column-family-keyspace column-family)
                          :key key
                          :column-path column-path))
      (cassandra::columnorsupercolumn-column cosc))))


(defmethod set-attribute ((family column-family) key column-name value &optional (timestamp (uuid::get-timestamp)))
  (let ((column-path (column-family-columnpath family)))
    (setf (cassandra::columnpath-column column-path) column-name)
    (insert (column-family-keyspace family)
            :key key
            :column-path column-path
            :value value
            :timestamp timestamp)))

(defmethod set-attribute ((column-family column-family) key column-name (value null) &optional timestamp)
  "Given a null value, delete the column"
  (declare (ignore timestamp))
  (let ((column-path (column-family-columnpath column-family)))
    (setf (cassandra::columnpath-column column-path) column-name)
    (remove (column-family-keyspace column-family)
            :key key
            :column-path column-path)))


(defmethod get-attributes ((column-family column-family) key &key (start "") (finish "") column-names reversed
                                            (count (column-family-slice-size column-family)))
    (let ((column-parent (column-family-columnparent column-family))
          (slice-predicate (column-family-slicepredicate column-family))
          (slice-range (column-family-slicerange column-family)))
      (cond (column-names
             (setf (cassandra::slicepredicate-column-names slice-predicate) column-names)
             (slot-makunbound slice-predicate 'cassandra::slice-range))
            (t
             (slot-makunbound slice-predicate 'cassandra::column-names)
             (setf (cassandra::slicepredicate-slice-range slice-predicate) slice-range
                   (cassandra::slicerange-start slice-range) start 
                   (cassandra::slicerange-finish slice-range) finish
                   (cassandra::slicerange-reversed slice-range) reversed
                   (cassandra::slicerange-count slice-range) count)))
      (loop for cosc in (get-slice (column-family-keyspace column-family)
                                   :key key
                                   :column-parent column-parent
                                   :predicate slice-predicate)
            collect (cassandra::columnorsupercolumn-column cosc))))


  
(defmethod set-attributes ((column-family column-family) key &rest property-list)
  (let ((timestamp (cond ((eq (first property-list) :timestamp) (pop property-list) (pop property-list))
                         (t (uuid::get-timestamp)))))
    (batch-mutate (column-family-keyspace column-family)
                  :mutation-map (thrift:map `(,key . ((,(column-family-name column-family)
                                                       ,@(loop for (column-name value) on property-list by #'cddr
                                                               when value     ; skip null values
                                                               collect (cassandra:make-mutation
                                                                        :column-or-supercolumn
                                                                        (cassandra:make-columnorsupercolumn
                                                                         :column (cassandra:make-column
                                                                                  :name column-name
                                                                                  :value value
                                                                                  :timestamp timestamp)))))))))))

;;;
;;; super-column family method expect the first key to map to a second key sequence, each of which
;;; locates a sequence of columns

(defmethod get-attribute ((family super-column-family) (keys cons) column-name)
  (destructuring-bind (key super-column) keys
    (let ((column-path (column-family-columnpath family))
          (cosc nil))
      (setf (cassandra::columnpath-column column-path) column-name
            (cassandra::columnpath-super-column column-path) super-column)
      (when (setf cosc (get (column-family-keyspace family)
                            :key key
                            :column-path column-path))
      (cassandra::columnorsupercolumn-column cosc)))))


(defmethod set-attribute ((family super-column-family) (keys cons) column-name column-value &optional (timestamp (uuid::get-timestamp)))
  (destructuring-bind (key super-column) keys
    (let ((column-path (column-family-columnpath family)))
      (setf (cassandra::columnpath-column column-path) column-name
            (cassandra::columnpath-super-column column-path) super-column)
      (insert (column-family-keyspace family)
              :key key
              :column-path column-path
              :value column-value
              :timestamp timestamp))))

(defmethod set-attribute ((family super-column-family) (keys cons) column-name (value null) &optional timestamp)
  "Given a null value, delete the column"
  (declare (ignore timestamp))
  (destructuring-bind (key super-column) keys
    (let ((column-path (column-family-columnpath family)))
      (setf (cassandra::columnpath-column column-path) column-name
            (cassandra::columnpath-super-column column-path) super-column)
      (remove (column-family-keyspace family)
              :key key
              :column-path column-path))))


(defmethod get-attributes ((family super-column-family) (keys cons) &key (start "") (finish "") column-names reversed
                             (count (column-family-slice-size family)))
  "Where the key is a list, the first element is the family key and the second is the syper-column key."
  (destructuring-bind (key super-column) keys
    (let ((column-parent (column-family-columnparent family))
          (slice-predicate (column-family-slicepredicate family))
          (slice-range (column-family-slicerange family)))
      (setf (cassandra::columnparent-super-column column-parent) super-column)
      (if column-names
        (setf (cassandra::slicepredicate-column-names slice-predicate) column-names
              (cassandra::slicepredicate-slice-range slice-predicate) nil)
        (setf (cassandra::slicepredicate-column-names slice-predicate) nil
              (cassandra::slicepredicate-slice-range slice-predicate) slice-range
              (cassandra::slicerange-start slice-range) start 
              (cassandra::slicerange-finish slice-range) finish
              (cassandra::slicerange-reversed slice-range) reversed
              (cassandra::slicerange-count slice-range) count))
      (loop for cosc in (get-slice (column-family-keyspace family)
                                   :key key
                                   :column-parent column-parent
                                   :predicate slice-predicate)
            collect (cassandra::columnorsupercolumn-column cosc)))))


(defmethod get-attributes ((family super-column-family) key &key (start "") (finish "") column-names reversed
                             (count (column-family-slice-size family)))
  "Where the key is atomic, it applies to all supercolumns."
    (let ((column-parent (column-family-columnparent family))
          (slice-predicate (column-family-slicepredicate family))
          (slice-range (column-family-slicerange family)))
      (slot-makunbound column-parent 'cassandra::super-column)
      (cond (column-names
             (setf (cassandra::slicepredicate-column-names slice-predicate) column-names)
             (slot-makunbound slice-predicate 'cassandra::slice-range))
            (t
             (slot-makunbound slice-predicate 'cassandra::column-names)
             (setf (cassandra::slicepredicate-slice-range slice-predicate) slice-range
                   (cassandra::slicerange-start slice-range) start 
                   (cassandra::slicerange-finish slice-range) finish
                   (cassandra::slicerange-reversed slice-range) reversed
                   (cassandra::slicerange-count slice-range) count)))
      (loop for cosc in (get-slice (column-family-keyspace family)
                                   :key key
                                   :column-parent column-parent
                                   :predicate slice-predicate)
            if (cassandra::columnorsupercolumn-super-column cosc)
            append (cassandra::supercolumn-columns (cassandra::columnorsupercolumn-super-column cosc))
            else collect (cassandra::columnorsupercolumn-column cosc))))


(defmethod set-attributes ((family super-column-family) (keys cons) &rest property-list)
  (destructuring-bind (key super-column) keys
    (let ((timestamp (cond ((eq (first property-list) :timestamp) (pop property-list) (pop property-list))
                         (t (uuid::get-timestamp)))))
      (batch-mutate (column-family-keyspace family)
                    :mutation-map (thrift:map `(,key . ((,(column-family-name family)
                                                         ,(cassandra:make-mutation
                                                           :column-or-supercolumn
                                                           (cassandra:make-columnorsupercolumn
                                                            :super-column 
                                                            (cassandra:make-supercolumn
                                                             :name super-column
                                                             :columns
                                                             (loop for (column-name value) on property-list by #'cddr
                                                                   when value     ; skip null values
                                                                   collect (cassandra:make-column
                                                                            :name column-name
                                                                            :value value
                                                                            :timestamp timestamp)))))))))))))
