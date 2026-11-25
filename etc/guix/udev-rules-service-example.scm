(define-module (example services upzi-udev)
  #:use-module (gnu)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  ;; Optional if you need it as a module in your guix system
  ;; configuration.
  #:export (upzi-service))

;; Add this service to the `services' field of your operating-system:
;;
;;   (services
;;    (cons upzi-service
;;          %base-services))
;;
;; The rule only grants access to the INNO TECH / Cypress 0665:5161
;; device.
;;
;; If your UPS reports different ID's replace them here and if the
;; protocol is different, consider contributing it :)
(define upzi-service
  (udev-rules-service
   'upzi
   (list
    (udev-rule
     "70-upzi.rules"
     (string-append
      "SUBSYSTEM==\"hidraw\","
      "ATTRS{idVendor}==\"0665\","
      "ATTRS{idProduct}==\"5161\","
      "TAG+=\"uaccess\"\n")))))
