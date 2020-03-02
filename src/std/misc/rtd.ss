;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; safe type descriptor accessors

(import :std/contract)
(export (rename: checked-object-type object-type)
        type? type-id type-name type-super
        type-descriptor?
        (rename: checked-type-descriptor-mixin type-descriptor-mixin)
        (rename: checked-type-descriptor-fields type-descriptor-fields)
        (rename: checked-type-descriptor-plist type-descriptor-plist)
        (rename: checked-type-descriptor-ctor type-descriptor-ctor)
        (rename: checked-type-descriptor-slots type-descriptor-slots)
        (rename: checked-type-descriptor-methods type-descriptor-methods))

(extern namespace: #f
  type-descriptor-mixin
  type-descriptor-fields
  type-descriptor-plist
  type-descriptor-ctor
  type-descriptor-slots
  type-descriptor-methods)

(def/c (checked-object-type obj)
  (@contract (object? obj))
  (object-type obj))

(def (type? obj)
  (##type? obj))

(defrules defcheck-type ()
  ((_ id getf)
   (def/c (id obj)
     (@contract (type? obj))
     (getf obj))))

(defrules defcheck-type-descriptor ()
  ((_ id getf)
   (def/c (id obj)
     (@contract (type-descriptor? obj))
     (getf obj))))

(defcheck-type type-id ##type-id)
(defcheck-type type-name ##type-name)
(defcheck-type type-super ##type-super)

(defcheck-type-descriptor checked-type-descriptor-mixin type-descriptor-mixin)
(defcheck-type-descriptor checked-type-descriptor-fields type-descriptor-fields)
(defcheck-type-descriptor checked-type-descriptor-plist type-descriptor-plist)
(defcheck-type-descriptor checked-type-descriptor-ctor type-descriptor-ctor)
(defcheck-type-descriptor checked-type-descriptor-slots type-descriptor-slots)
(defcheck-type-descriptor checked-type-descriptor-methods type-descriptor-methods)
