(declare (block) (standard-bindings) (extended-bindings))
(begin
  (define gx#identifier-wrap::t
    (make-struct-type
     'gx#identifier-wrap::t
     AST::t
     '1
     'syntax
     '((final: . #t))
     '#f))
  (define gx#identifier-wrap? (make-struct-predicate gx#identifier-wrap::t))
  (define gx#make-identifier-wrap
    (lambda _$args4002_
      (apply make-struct-instance gx#identifier-wrap::t _$args4002_)))
  (define gx#identifier-wrap-marks
    (make-struct-field-accessor gx#identifier-wrap::t '0))
  (define gx#identifier-wrap-marks-set!
    (make-struct-field-mutator gx#identifier-wrap::t '0))
  (define gx#syntax-wrap::t
    (make-struct-type
     'gx#syntax-wrap::t
     AST::t
     '1
     'syntax
     '((final: . #t))
     '#f))
  (define gx#syntax-wrap? (make-struct-predicate gx#syntax-wrap::t))
  (define gx#make-syntax-wrap
    (lambda _$args3999_
      (apply make-struct-instance gx#syntax-wrap::t _$args3999_)))
  (define gx#syntax-wrap-mark
    (make-struct-field-accessor gx#syntax-wrap::t '0))
  (define gx#syntax-wrap-mark-set!
    (make-struct-field-mutator gx#syntax-wrap::t '0))
  (define gx#syntax-quote::t
    (make-struct-type
     'gx#syntax-quote::t
     AST::t
     '2
     'syntax
     '((final: . #t))
     '#f))
  (define gx#syntax-quote? (make-struct-predicate gx#syntax-quote::t))
  (define gx#make-syntax-quote
    (lambda _$args3996_
      (apply make-struct-instance gx#syntax-quote::t _$args3996_)))
  (define gx#syntax-quote-context
    (make-struct-field-accessor gx#syntax-quote::t '0))
  (define gx#syntax-quote-marks
    (make-struct-field-accessor gx#syntax-quote::t '1))
  (define gx#syntax-quote-context-set!
    (make-struct-field-mutator gx#syntax-quote::t '0))
  (define gx#syntax-quote-marks-set!
    (make-struct-field-mutator gx#syntax-quote::t '1))
  (define gx#identifier? (lambda (_stx3994_) (symbol? (gx#stx-e _stx3994_))))
  (define gx#identifier-quote?
    (lambda (_stx3992_)
      (if (##structure-direct-instance-of? _stx3992_ 'gx#syntax-quote::t)
          (symbol? (##structure-ref _stx3992_ '1 AST::t '#f))
          '#f)))
  (define gx#sealed-syntax?
    (lambda (_stx3987_)
      (let ((_$e3989_
             (##structure-direct-instance-of? _stx3987_ 'gx#syntax-quote::t)))
        (if _$e3989_
            _$e3989_
            (if (##structure-instance-of? _stx3987_ 'gerbil#AST::t)
                (gx#sealed-syntax? (##structure-ref _stx3987_ '1 AST::t '#f))
                '#f)))))
  (define gx#syntax-e
    (lambda (_stx3983_)
      (let ((_stx3985_ (gx#stx-unwrap__0 _stx3983_)))
        (if (##structure-instance-of? _stx3985_ 'gerbil#AST::t)
            (##structure-ref _stx3985_ '1 AST::t '#f)
            _stx3985_))))
  (define gx#syntax->datum
    (lambda (_stx3981_)
      (if (##structure-instance-of? _stx3981_ 'gerbil#AST::t)
          (gx#syntax->datum (##structure-ref _stx3981_ '1 AST::t '#f))
          (if (pair? _stx3981_)
              (cons (gx#syntax->datum (car _stx3981_))
                    (gx#syntax->datum (cdr _stx3981_)))
              (if (vector? _stx3981_)
                  (vector-map gx#syntax->datum _stx3981_)
                  (if (box? _stx3981_)
                      (box (gx#syntax->datum (unbox _stx3981_)))
                      _stx3981_))))))
  (begin
    (define gx#datum->syntax__opt-lambda3949
      (lambda (_stx3951_ _datum3952_ _src3953_)
        (letrec ((_wrap-datum3955_
                  (lambda (_e3962_ _marks3963_)
                    (let _recur3965_ ((_e3967_ _e3962_))
                      (if (symbol? _e3967_)
                          (##structure
                           gx#identifier-wrap::t
                           _e3967_
                           _src3953_
                           _marks3963_)
                          (if (pair? _e3967_)
                              (cons (_recur3965_ (car _e3967_))
                                    (_recur3965_ (cdr _e3967_)))
                              (if (vector? _e3967_)
                                  (vector-map _recur3965_ _e3967_)
                                  (if (box? _e3967_)
                                      (box (_recur3965_ (unbox _e3967_)))
                                      _e3967_)))))))
                 (_wrap-outer3956_
                  (lambda (_e3960_)
                    (if (##structure-instance-of? _e3960_ 'gerbil#AST::t)
                        _e3960_
                        (##structure AST::t _e3960_ _src3953_)))))
          (if (##structure-instance-of? _datum3952_ 'gerbil#AST::t)
              _datum3952_
              (if (not _stx3951_)
                  (##structure AST::t _datum3952_ _src3953_)
                  (if (gx#identifier? _stx3951_)
                      (let ((_stx3958_ (gx#stx-unwrap__0 _stx3951_)))
                        (if (gx#identifier-quote? _stx3958_)
                            (##structure
                             gx#syntax-quote::t
                             _datum3952_
                             _src3953_
                             (##direct-structure-ref
                              _stx3958_
                              '3
                              gx#syntax-quote::t
                              '#f)
                             (##direct-structure-ref
                              _stx3958_
                              '4
                              gx#syntax-quote::t
                              '#f))
                            (_wrap-outer3956_
                             (_wrap-datum3955_
                              _datum3952_
                              (##direct-structure-ref
                               _stx3958_
                               '3
                               gx#identifier-wrap::t
                               '#f)))))
                      (error '"Bad template syntax; expected identifier"
                             _stx3951_)))))))
    (begin
      (define gx#datum->syntax__0
        (lambda (_stx3972_ _datum3973_)
          (let ((_src3975_ '#f))
            (gx#datum->syntax__opt-lambda3949
             _stx3972_
             _datum3973_
             _src3975_))))
      (define gx#datum->syntax
        (lambda _g4005_
          (let ((_g4004_ (length _g4005_)))
            (cond ((fx= _g4004_ 2) (apply gx#datum->syntax__0 _g4005_))
                  ((fx= _g4004_ 3)
                   (apply gx#datum->syntax__opt-lambda3949 _g4005_))
                  (else
                   (##raise-wrong-number-of-arguments-exception
                    gx#datum->syntax
                    _g4005_))))))))
  (begin
    (define gx#stx-unwrap__opt-lambda3925
      (lambda (_stx3927_ _marks3928_)
        (let _lp3930_ ((_e3932_ _stx3927_)
                       (_marks3933_ _marks3928_)
                       (_src3934_ (gx#stx-source _stx3927_)))
          (if (##structure-direct-instance-of? _e3932_ 'gx#syntax-wrap::t)
              (_lp3930_
               (##structure-ref _e3932_ '1 AST::t '#f)
               (gx#apply-mark
                (##direct-structure-ref _e3932_ '3 gx#syntax-wrap::t '#f)
                _marks3933_)
               (##structure-ref _e3932_ '2 AST::t '#f))
              (if (##structure-direct-instance-of?
                   _e3932_
                   'gx#identifier-wrap::t)
                  (if (null? _marks3933_)
                      _e3932_
                      (##structure
                       gx#identifier-wrap::t
                       (##structure-ref _e3932_ '1 AST::t '#f)
                       (##structure-ref _e3932_ '2 AST::t '#f)
                       (foldl1 gx#apply-mark
                               (##direct-structure-ref
                                _e3932_
                                '3
                                gx#identifier-wrap::t
                                '#f)
                               _marks3933_)))
                  (if (##structure-direct-instance-of?
                       _e3932_
                       'gx#syntax-quote::t)
                      _e3932_
                      (if (##structure-instance-of? _e3932_ 'gerbil#AST::t)
                          (_lp3930_
                           (##structure-ref _e3932_ '1 AST::t '#f)
                           _marks3933_
                           (##structure-ref _e3932_ '2 AST::t '#f))
                          (if (symbol? _e3932_)
                              (##structure
                               gx#identifier-wrap::t
                               _e3932_
                               _src3934_
                               (reverse _marks3933_))
                              (if (null? _marks3933_)
                                  _e3932_
                                  (if (pair? _e3932_)
                                      (cons (gx#stx-wrap
                                             (car _e3932_)
                                             _marks3933_)
                                            (gx#stx-wrap
                                             (cdr _e3932_)
                                             _marks3933_))
                                      (if (vector? _e3932_)
                                          (vector-map
                                           (lambda (_g39353937_)
                                             (gx#stx-wrap
                                              _g39353937_
                                              _marks3933_))
                                           _e3932_)
                                          (if (box? _e3932_)
                                              (box (gx#stx-wrap
                                                    (unbox _e3932_)
                                                    _marks3933_))
                                              _e3932_))))))))))))
    (begin
      (define gx#stx-unwrap__0
        (lambda (_stx3943_)
          (let ((_marks3945_ '()))
            (gx#stx-unwrap__opt-lambda3925 _stx3943_ _marks3945_))))
      (define gx#stx-unwrap
        (lambda _g4007_
          (let ((_g4006_ (length _g4007_)))
            (cond ((fx= _g4006_ 1) (apply gx#stx-unwrap__0 _g4007_))
                  ((fx= _g4006_ 2)
                   (apply gx#stx-unwrap__opt-lambda3925 _g4007_))
                  (else
                   (##raise-wrong-number-of-arguments-exception
                    gx#stx-unwrap
                    _g4007_))))))))
  (define gx#stx-wrap
    (lambda (_stx3920_ _marks3921_)
      (foldl1 (lambda (_mark3923_ _stx3924_)
                (gx#stx-apply-mark _stx3924_ _mark3923_))
              _stx3920_
              _marks3921_)))
  (define gx#stx-rewrap
    (lambda (_stx3914_ _marks3915_)
      (foldr1 (lambda (_mark3917_ _stx3918_)
                (gx#stx-apply-mark _stx3918_ _mark3917_))
              _stx3914_
              _marks3915_)))
  (define gx#stx-apply-mark
    (lambda (_stx3911_ _mark3912_)
      (if (##structure-direct-instance-of? _stx3911_ 'gx#syntax-quote::t)
          _stx3911_
          (if (if (##structure-direct-instance-of?
                   _stx3911_
                   'gx#syntax-wrap::t)
                  (eq? _mark3912_
                       (##direct-structure-ref
                        _stx3911_
                        '3
                        gx#syntax-wrap::t
                        '#f))
                  '#f)
              (##structure-ref _stx3911_ '1 AST::t '#f)
              (##structure
               gx#syntax-wrap::t
               _stx3911_
               (gx#stx-source _stx3911_)
               _mark3912_)))))
  (define gx#apply-mark
    (lambda (_mark3875_ _marks3876_)
      (let* ((_marks38773885_ _marks3876_)
             (_E38803889_
              (lambda () (error '"No clause matching" _marks38773885_)))
             (_else38793893_ (lambda () (cons _mark3875_ _marks3876_)))
             (_K38813899_
              (lambda (_rest3896_ _hd3897_)
                (if (eq? _mark3875_ _hd3897_)
                    _rest3896_
                    (cons _mark3875_ _marks3876_)))))
        (if (##pair? _marks38773885_)
            (let ((_hd38823902_ (##car _marks38773885_))
                  (_tl38833904_ (##cdr _marks38773885_)))
              (let* ((_hd3907_ _hd38823902_) (_rest3909_ _tl38833904_))
                (_K38813899_ _rest3909_ _hd3907_)))
            (_else38793893_)))))
  (define gx#stx-e
    (lambda (_stx3873_)
      (if (##structure-instance-of? _stx3873_ 'gerbil#AST::t)
          (gx#stx-e (##structure-ref _stx3873_ '1 AST::t '#f))
          _stx3873_)))
  (define gx#stx-source
    (lambda (_stx3871_)
      (if (##structure-instance-of? _stx3871_ 'gerbil#AST::t)
          (##structure-ref _stx3871_ '2 AST::t '#f)
          '#f)))
  (define gx#stx-wrap-source
    (lambda (_stx3865_ _src3866_)
      (if (let ((_$e3868_ (##structure-instance-of? _stx3865_ 'gerbil#AST::t)))
            (if _$e3868_ _$e3868_ (not _src3866_)))
          _stx3865_
          (##structure AST::t _stx3865_ _src3866_))))
  (define gx#stx-datum?
    (lambda (_stx3863_) (gx#self-quoting? (gx#stx-e _stx3863_))))
  (define gx#self-quoting?
    (lambda (_x3843_)
      (let ((_$e3845_ (boolean? _x3843_)))
        (if _$e3845_
            _$e3845_
            (let ((_$e3848_ (char? _x3843_)))
              (if _$e3848_
                  _$e3848_
                  (let ((_$e3851_ (number? _x3843_)))
                    (if _$e3851_
                        _$e3851_
                        (let ((_$e3854_ (keyword? _x3843_)))
                          (if _$e3854_
                              _$e3854_
                              (let ((_$e3857_ (string? _x3843_)))
                                (if _$e3857_
                                    _$e3857_
                                    (let ((_$e3860_ (eq? _x3843_ '#!void)))
                                      (if _$e3860_
                                          _$e3860_
                                          (dssl-object? _x3843_)))))))))))))))
  (define gx#stx-boolean? (lambda (_e3841_) (boolean? (gx#stx-e _e3841_))))
  (define gx#stx-keyword? (lambda (_e3839_) (keyword? (gx#stx-e _e3839_))))
  (define gx#stx-char? (lambda (_e3837_) (char? (gx#stx-e _e3837_))))
  (define gx#stx-number? (lambda (_e3835_) (number? (gx#stx-e _e3835_))))
  (define gx#stx-fixnum? (lambda (_e3833_) (fixnum? (gx#stx-e _e3833_))))
  (define gx#stx-string? (lambda (_e3831_) (string? (gx#stx-e _e3831_))))
  (define gx#stx-null? (lambda (_e3829_) (null? (gx#stx-e _e3829_))))
  (define gx#stx-pair? (lambda (_e3827_) (pair? (gx#stx-e _e3827_))))
  (define gx#stx-list?
    (lambda (_e3787_)
      (let* ((_g37883797_ (gx#stx-e _e3787_))
             (_E37913801_
              (lambda () (error '"No clause matching" _g37883797_)))
             (_try-match37903812_
              (lambda ()
                (let* ((_K37923807_ (lambda (_tail3805_) (null? _tail3805_)))
                       (_tail3810_ _g37883797_))
                  (null? _tail3810_))))
             (_K37933817_ (lambda (_rest3815_) (gx#stx-list? _rest3815_))))
        (if (##pair? _g37883797_)
            (let ((_hd37943820_ (##car _g37883797_))
                  (_tl37953822_ (##cdr _g37883797_)))
              (let ((_rest3825_ _tl37953822_)) (gx#stx-list? _rest3825_)))
            (_try-match37903812_)))))
  (define gx#stx-pair/null?
    (lambda (_e3780_)
      (let* ((_e3782_ (gx#stx-e _e3780_)) (_$e3784_ (pair? _e3782_)))
        (if _$e3784_ _$e3784_ (null? _e3782_)))))
  (define gx#stx-vector? (lambda (_e3778_) (vector? (gx#stx-e _e3778_))))
  (define gx#stx-box? (lambda (_e3776_) (box? (gx#stx-e _e3776_))))
  (define gx#stx-eq?
    (lambda (_x3773_ _y3774_) (eq? (gx#stx-e _x3773_) (gx#stx-e _y3774_))))
  (define gx#stx-eqv?
    (lambda (_x3770_ _y3771_) (eqv? (gx#stx-e _x3770_) (gx#stx-e _y3771_))))
  (define gx#stx-equal?
    (lambda (_x3767_ _y3768_) (equal? (gx#stx-e _x3767_) (gx#stx-e _y3768_))))
  (define gx#stx-false? (lambda (_x3765_) (not (gx#stx-e _x3765_))))
  (define gx#stx-identifier
    (lambda (_template3762_ . _args3763_)
      (gx#datum->syntax__opt-lambda3949
       _template3762_
       (apply make-symbol (map gx#stx-e _args3763_))
       (gx#stx-source _template3762_))))
  (define gx#stx-identifier-marks
    (lambda (_stx3758_)
      (let ((_stx3760_ (gx#stx-unwrap__0 _stx3758_)))
        (if (##structure-direct-instance-of? _stx3760_ 'gx#identifier-wrap::t)
            (##direct-structure-ref _stx3760_ '3 gx#identifier-wrap::t '#f)
            (##direct-structure-ref _stx3760_ '4 gx#syntax-quote::t '#f)))))
  (define gx#stx-identifier-context
    (lambda (_stx3754_)
      (let ((_stx3756_ (gx#stx-unwrap__0 _stx3754_)))
        (if (gx#identifier-quote? _stx3756_)
            (##direct-structure-ref _stx3756_ '3 gx#syntax-quote::t '#f)
            '#f))))
  (define gx#identifier-list?
    (lambda (_stx3709_)
      (let* ((_g37103720_ (gx#stx-e _stx3709_))
             (_E37143724_
              (lambda () (error '"No clause matching" _g37103720_)))
             (_else37133728_ (lambda () '#f))
             (_try-match37123736_
              (lambda ()
                (let ((_K37153733_ (lambda () '#t)))
                  (if (##null? _g37103720_) (_K37153733_) (_else37133728_)))))
             (_K37163742_
              (lambda (_rest3739_ _hd3740_)
                (if (gx#identifier? _hd3740_)
                    (gx#identifier-list? _rest3739_)
                    '#f))))
        (if (##pair? _g37103720_)
            (let ((_hd37173745_ (##car _g37103720_))
                  (_tl37183747_ (##cdr _g37103720_)))
              (let* ((_hd3750_ _hd37173745_) (_rest3752_ _tl37183747_))
                (_K37163742_ _rest3752_ _hd3750_)))
            (_try-match37123736_)))))
  (begin
    (define gx#genident__opt-lambda3684
      (lambda (_e3686_ _src3687_)
        (gx#stx-wrap-source
         (gensym (let ((_e3689_ (gx#stx-e _e3686_)))
                   (if (interned-symbol? _e3689_) _e3689_ 'g)))
         (let ((_$e3691_ (gx#stx-source _e3686_)))
           (if _$e3691_ _$e3691_ _src3687_)))))
    (begin
      (define gx#genident__0
        (lambda ()
          (let* ((_e3698_ 'g) (_src3700_ '#f))
            (gx#genident__opt-lambda3684 _e3698_ _src3700_))))
      (define gx#genident__1
        (lambda (_e3702_)
          (let ((_src3704_ '#f))
            (gx#genident__opt-lambda3684 _e3702_ _src3704_))))
      (define gx#genident
        (lambda _g4009_
          (let ((_g4008_ (length _g4009_)))
            (cond ((fx= _g4008_ 0) (apply gx#genident__0 _g4009_))
                  ((fx= _g4008_ 1) (apply gx#genident__1 _g4009_))
                  ((fx= _g4008_ 2) (apply gx#genident__opt-lambda3684 _g4009_))
                  (else
                   (##raise-wrong-number-of-arguments-exception
                    gx#genident
                    _g4009_))))))))
  (define gx#gentemps
    (lambda (_stx-lst3683_) (gx#stx-map1 gx#genident _stx-lst3683_)))
  (define gx#syntax->list (lambda (_stx3681_) (gx#stx-map1 values _stx3681_)))
  (define gx#stx-car (lambda (_stx3679_) (car (gx#syntax-e _stx3679_))))
  (define gx#stx-cdr (lambda (_stx3677_) (cdr (gx#syntax-e _stx3677_))))
  (define gx#stx-length
    (lambda (_stx3640_)
      (let _lp3642_ ((_rest3644_ _stx3640_) (_n3645_ '0))
        (let* ((_g36463654_ (gx#stx-e _rest3644_))
               (_E36493658_
                (lambda () (error '"No clause matching" _g36463654_)))
               (_else36483662_ (lambda () _n3645_))
               (_K36503667_
                (lambda (_rest3665_) (_lp3642_ _rest3665_ (fx+ _n3645_ '1)))))
          (if (##pair? _g36463654_)
              (let ((_hd36513670_ (##car _g36463654_))
                    (_tl36523672_ (##cdr _g36463654_)))
                (let ((_rest3675_ _tl36523672_)) (_K36503667_ _rest3675_)))
              (_else36483662_))))))
  (define gx#stx-for-each
    (lambda _g4011_
      (let ((_g4010_ (length _g4011_)))
        (cond ((fx= _g4010_ 2) (apply gx#stx-for-each1 _g4011_))
              ((fx= _g4010_ 3) (apply gx#stx-for-each2 _g4011_))
              (else
               (##raise-wrong-number-of-arguments-exception
                gx#stx-for-each
                _g4011_))))))
  (define gx#stx-for-each1
    (lambda (_f3583_ _stx3584_)
      (let _lp3586_ ((_rest3588_ _stx3584_))
        (let* ((_g35893599_ (gx#syntax-e _rest3588_))
               (_E35933603_
                (lambda () (error '"No clause matching" _g35893599_)))
               (_else35923607_ (lambda () (_f3583_ _rest3588_)))
               (_try-match35913615_
                (lambda ()
                  (let ((_K35943612_ (lambda () '#!void)))
                    (if (##null? _g35893599_)
                        (_K35943612_)
                        (_else35923607_)))))
               (_K35953621_
                (lambda (_rest3618_ _hd3619_)
                  (begin (_f3583_ _hd3619_) (_lp3586_ _rest3618_)))))
          (if (##pair? _g35893599_)
              (let ((_hd35963624_ (##car _g35893599_))
                    (_tl35973626_ (##cdr _g35893599_)))
                (let* ((_hd3629_ _hd35963624_) (_rest3631_ _tl35973626_))
                  (_K35953621_ _rest3631_ _hd3629_)))
              (_try-match35913615_))))))
  (define gx#stx-for-each2
    (lambda (_f3488_ _xstx3489_ _ystx3490_)
      (let _lp3492_ ((_xrest3494_ _xstx3489_) (_yrest3495_ _ystx3490_))
        (let* ((_g34963506_ (gx#syntax-e _xrest3494_))
               (_E35003510_
                (lambda () (error '"No clause matching" _g34963506_)))
               (_else34993514_ (lambda () '#!void))
               (_try-match34983537_
                (lambda ()
                  (let ((_K35013534_
                         (lambda ()
                           (let* ((_yrest35183523_ _yrest3495_)
                                  (_E35203527_
                                   (lambda ()
                                     (error '"No clause matching"
                                            _yrest35183523_)))
                                  (_K35213531_
                                   (lambda ()
                                     (_f3488_ _xrest3494_ _yrest3495_))))
                             (if (not (gx#stx-null? _yrest35183523_))
                                 (_K35213531_)
                                 (_E35203527_))))))
                    (if (not (null? _g34963506_))
                        (_K35013534_)
                        (_else34993514_)))))
               (_K35023571_
                (lambda (_xrest3540_ _xhd3541_)
                  (let* ((_g35423549_ (gx#syntax-e _yrest3495_))
                         (_E35443553_
                          (lambda ()
                            (error '"No clause matching" _g35423549_)))
                         (_K35453559_
                          (lambda (_yrest3556_ _yhd3557_)
                            (begin
                              (_f3488_ _xhd3541_ _yhd3557_)
                              (_lp3492_ _xrest3540_ _yrest3556_)))))
                    (if (##pair? _g35423549_)
                        (let ((_hd35463562_ (##car _g35423549_))
                              (_tl35473564_ (##cdr _g35423549_)))
                          (let* ((_yhd3567_ _hd35463562_)
                                 (_yrest3569_ _tl35473564_))
                            (_K35453559_ _yrest3569_ _yhd3567_)))
                        (_E35443553_))))))
          (if (##pair? _g34963506_)
              (let ((_hd35033574_ (##car _g34963506_))
                    (_tl35043576_ (##cdr _g34963506_)))
                (let* ((_xhd3579_ _hd35033574_) (_xrest3581_ _tl35043576_))
                  (_K35023571_ _xrest3581_ _xhd3579_)))
              (_try-match34983537_))))))
  (define gx#stx-map
    (lambda _g4013_
      (let ((_g4012_ (length _g4013_)))
        (cond ((fx= _g4012_ 2) (apply gx#stx-map1 _g4013_))
              ((fx= _g4012_ 3) (apply gx#stx-map2 _g4013_))
              (else
               (##raise-wrong-number-of-arguments-exception
                gx#stx-map
                _g4013_))))))
  (define gx#stx-map1
    (lambda (_f3431_ _stx3432_)
      (let _recur3434_ ((_rest3436_ _stx3432_))
        (let* ((_g34373447_ (gx#syntax-e _rest3436_))
               (_E34413451_
                (lambda () (error '"No clause matching" _g34373447_)))
               (_else34403455_ (lambda () (_f3431_ _rest3436_)))
               (_try-match34393463_
                (lambda ()
                  (let ((_K34423460_ (lambda () '())))
                    (if (##null? _g34373447_)
                        (_K34423460_)
                        (_else34403455_)))))
               (_K34433469_
                (lambda (_rest3466_ _hd3467_)
                  (cons (_f3431_ _hd3467_) (_recur3434_ _rest3466_)))))
          (if (##pair? _g34373447_)
              (let ((_hd34443472_ (##car _g34373447_))
                    (_tl34453474_ (##cdr _g34373447_)))
                (let* ((_hd3477_ _hd34443472_) (_rest3479_ _tl34453474_))
                  (_K34433469_ _rest3479_ _hd3477_)))
              (_try-match34393463_))))))
  (define gx#stx-map2
    (lambda (_f3336_ _xstx3337_ _ystx3338_)
      (let _recur3340_ ((_xrest3342_ _xstx3337_) (_yrest3343_ _ystx3338_))
        (let* ((_g33443354_ (gx#syntax-e _xrest3342_))
               (_E33483358_
                (lambda () (error '"No clause matching" _g33443354_)))
               (_else33473362_ (lambda () '()))
               (_try-match33463385_
                (lambda ()
                  (let ((_K33493382_
                         (lambda ()
                           (let* ((_yrest33663371_ _yrest3343_)
                                  (_E33683375_
                                   (lambda ()
                                     (error '"No clause matching"
                                            _yrest33663371_)))
                                  (_K33693379_
                                   (lambda ()
                                     (_f3336_ _xrest3342_ _yrest3343_))))
                             (if (not (gx#stx-null? _yrest33663371_))
                                 (_K33693379_)
                                 (_E33683375_))))))
                    (if (not (null? _g33443354_))
                        (_K33493382_)
                        (_else33473362_)))))
               (_K33503419_
                (lambda (_xrest3388_ _xhd3389_)
                  (let* ((_g33903397_ (gx#syntax-e _yrest3343_))
                         (_E33923401_
                          (lambda ()
                            (error '"No clause matching" _g33903397_)))
                         (_K33933407_
                          (lambda (_yrest3404_ _yhd3405_)
                            (cons (_f3336_ _xhd3389_ _yhd3405_)
                                  (_recur3340_ _xrest3388_ _yrest3404_)))))
                    (if (##pair? _g33903397_)
                        (let ((_hd33943410_ (##car _g33903397_))
                              (_tl33953412_ (##cdr _g33903397_)))
                          (let* ((_yhd3415_ _hd33943410_)
                                 (_yrest3417_ _tl33953412_))
                            (_K33933407_ _yrest3417_ _yhd3415_)))
                        (_E33923401_))))))
          (if (##pair? _g33443354_)
              (let ((_hd33513422_ (##car _g33443354_))
                    (_tl33523424_ (##cdr _g33443354_)))
                (let* ((_xhd3427_ _hd33513422_) (_xrest3429_ _tl33523424_))
                  (_K33503419_ _xrest3429_ _xhd3427_)))
              (_try-match33463385_))))))
  (define gx#stx-andmap
    (lambda (_f3286_ _stx3287_)
      (let _lp3289_ ((_rest3291_ _stx3287_))
        (let* ((_g32923302_ (gx#syntax-e _rest3291_))
               (_E32963306_
                (lambda () (error '"No clause matching" _g32923302_)))
               (_else32953310_ (lambda () (_f3286_ _rest3291_)))
               (_try-match32943318_
                (lambda ()
                  (let ((_K32973315_ (lambda () '#t)))
                    (if (##null? _g32923302_)
                        (_K32973315_)
                        (_else32953310_)))))
               (_K32983324_
                (lambda (_rest3321_ _hd3322_)
                  (if (_f3286_ _hd3322_) (_lp3289_ _rest3321_) '#f))))
          (if (##pair? _g32923302_)
              (let ((_hd32993327_ (##car _g32923302_))
                    (_tl33003329_ (##cdr _g32923302_)))
                (let* ((_hd3332_ _hd32993327_) (_rest3334_ _tl33003329_))
                  (_K32983324_ _rest3334_ _hd3332_)))
              (_try-match32943318_))))))
  (define gx#stx-ormap
    (lambda (_f3233_ _stx3234_)
      (let _lp3236_ ((_rest3238_ _stx3234_))
        (let* ((_g32393249_ (gx#syntax-e _rest3238_))
               (_E32433253_
                (lambda () (error '"No clause matching" _g32393249_)))
               (_else32423257_ (lambda () (_f3233_ _rest3238_)))
               (_try-match32413265_
                (lambda ()
                  (let ((_K32443262_ (lambda () '#f)))
                    (if (##null? _g32393249_)
                        (_K32443262_)
                        (_else32423257_)))))
               (_K32453274_
                (lambda (_rest3268_ _hd3269_)
                  (let ((_$e3271_ (_f3233_ _hd3269_)))
                    (if _$e3271_ _$e3271_ (_lp3236_ _rest3268_))))))
          (if (##pair? _g32393249_)
              (let ((_hd32463277_ (##car _g32393249_))
                    (_tl32473279_ (##cdr _g32393249_)))
                (let* ((_hd3282_ _hd32463277_) (_rest3284_ _tl32473279_))
                  (_K32453274_ _rest3284_ _hd3282_)))
              (_try-match32413265_))))))
  (define gx#stx-foldl
    (lambda (_f3181_ _iv3182_ _stx3183_)
      (let _lp3185_ ((_r3187_ _iv3182_) (_rest3188_ _stx3183_))
        (let* ((_g31893199_ (gx#syntax-e _rest3188_))
               (_E31933203_
                (lambda () (error '"No clause matching" _g31893199_)))
               (_else31923207_ (lambda () (_f3181_ _rest3188_ _r3187_)))
               (_try-match31913215_
                (lambda ()
                  (let ((_K31943212_ (lambda () _r3187_)))
                    (if (##null? _g31893199_)
                        (_K31943212_)
                        (_else31923207_)))))
               (_K31953221_
                (lambda (_rest3218_ _hd3219_)
                  (_lp3185_ (_f3181_ _hd3219_ _r3187_) _rest3218_))))
          (if (##pair? _g31893199_)
              (let ((_hd31963224_ (##car _g31893199_))
                    (_tl31973226_ (##cdr _g31893199_)))
                (let* ((_hd3229_ _hd31963224_) (_rest3231_ _tl31973226_))
                  (_K31953221_ _rest3231_ _hd3229_)))
              (_try-match31913215_))))))
  (define gx#stx-foldr
    (lambda (_f3130_ _iv3131_ _stx3132_)
      (let _recur3134_ ((_rest3136_ _stx3132_))
        (let* ((_g31373147_ (gx#syntax-e _rest3136_))
               (_E31413151_
                (lambda () (error '"No clause matching" _g31373147_)))
               (_else31403155_ (lambda () (_f3130_ _rest3136_ _iv3131_)))
               (_try-match31393163_
                (lambda ()
                  (let ((_K31423160_ (lambda () _iv3131_)))
                    (if (##null? _g31373147_)
                        (_K31423160_)
                        (_else31403155_)))))
               (_K31433169_
                (lambda (_rest3166_ _hd3167_)
                  (_f3130_ _hd3167_ (_recur3134_ _rest3166_)))))
          (if (##pair? _g31373147_)
              (let ((_hd31443172_ (##car _g31373147_))
                    (_tl31453174_ (##cdr _g31373147_)))
                (let* ((_hd3177_ _hd31443172_) (_rest3179_ _tl31453174_))
                  (_K31433169_ _rest3179_ _hd3177_)))
              (_try-match31393163_))))))
  (define gx#stx-reverse
    (lambda (_stx3128_) (gx#stx-foldl cons '() _stx3128_)))
  (define gx#stx-last
    (lambda (_stx3089_)
      (let _lp3091_ ((_rest3093_ _stx3089_))
        (let* ((_g30943102_ (gx#syntax-e _rest3093_))
               (_E30973106_
                (lambda () (error '"No clause matching" _g30943102_)))
               (_else30963110_ (lambda () _rest3093_))
               (_K30983116_
                (lambda (_rest3113_ _hd3114_)
                  (if (gx#stx-null? _rest3113_)
                      _hd3114_
                      (_lp3091_ _rest3113_)))))
          (if (##pair? _g30943102_)
              (let ((_hd30993119_ (##car _g30943102_))
                    (_tl31003121_ (##cdr _g30943102_)))
                (let* ((_hd3124_ _hd30993119_) (_rest3126_ _tl31003121_))
                  (_K30983116_ _rest3126_ _hd3124_)))
              (_else30963110_))))))
  (define gx#stx-last-pair
    (lambda (_stx3058_)
      (let _lp3060_ ((_hd3062_ _stx3058_))
        (let* ((_g30633070_ (gx#syntax-e _hd3062_))
               (_E30653074_
                (lambda () (error '"No clause matching" _g30633070_)))
               (_K30663079_
                (lambda (_rest3077_)
                  (if (gx#stx-pair? _rest3077_)
                      (_lp3060_ _rest3077_)
                      _hd3062_))))
          (if (##pair? _g30633070_)
              (let ((_hd30673082_ (##car _g30633070_))
                    (_tl30683084_ (##cdr _g30633070_)))
                (let ((_rest3087_ _tl30683084_)) (_K30663079_ _rest3087_)))
              (_E30653074_))))))
  (define gx#stx-list-tail
    (lambda (_stx3025_ _k3026_)
      (let _lp3028_ ((_rest3030_ _stx3025_) (_k3031_ _k3026_))
        (if (fxpositive? _k3031_)
            (let* ((_g30323039_ (gx#syntax-e _rest3030_))
                   (_E30343043_
                    (lambda () (error '"No clause matching" _g30323039_)))
                   (_K30353048_
                    (lambda (_rest3046_)
                      (_lp3028_ _rest3046_ (fx- _k3031_ '1)))))
              (if (##pair? _g30323039_)
                  (let ((_hd30363051_ (##car _g30323039_))
                        (_tl30373053_ (##cdr _g30323039_)))
                    (let ((_rest3056_ _tl30373053_)) (_K30353048_ _rest3056_)))
                  (_E30343043_)))
            _rest3030_))))
  (define gx#stx-list-ref
    (lambda (_stx3022_ _k3023_)
      (gx#stx-car (gx#stx-list-tail _stx3022_ _k3023_))))
  (begin
    (define gx#stx-plist?__opt-lambda2930
      (lambda (_stx2932_ _key?2933_)
        (let _lp2935_ ((_rest2937_ _stx2932_))
          (let* ((_g29382948_ (gx#stx-e _rest2937_))
                 (_E29422952_
                  (lambda () (error '"No clause matching" _g29382948_)))
                 (_else29412956_ (lambda () '#f))
                 (_try-match29402964_
                  (lambda ()
                    (let ((_K29432961_ (lambda () '#t)))
                      (if (##null? _g29382948_)
                          (_K29432961_)
                          (_else29412956_)))))
                 (_K29443000_
                  (lambda (_rest2967_ _hd2968_)
                    (if (_key?2933_ _hd2968_)
                        (let* ((_g29692977_ (gx#stx-e _rest2967_))
                               (_E29722981_
                                (lambda ()
                                  (error '"No clause matching" _g29692977_)))
                               (_else29712985_ (lambda () '#f))
                               (_K29732990_
                                (lambda (_rest2988_) (_lp2935_ _rest2988_))))
                          (if (##pair? _g29692977_)
                              (let ((_hd29742993_ (##car _g29692977_))
                                    (_tl29752995_ (##cdr _g29692977_)))
                                (let ((_rest2998_ _tl29752995_))
                                  (_K29732990_ _rest2998_)))
                              (_else29712985_)))
                        '#f))))
            (if (##pair? _g29382948_)
                (let ((_hd29453003_ (##car _g29382948_))
                      (_tl29463005_ (##cdr _g29382948_)))
                  (let* ((_hd3008_ _hd29453003_) (_rest3010_ _tl29463005_))
                    (_K29443000_ _rest3010_ _hd3008_)))
                (_try-match29402964_))))))
    (begin
      (define gx#stx-plist?__0
        (lambda (_stx3015_)
          (let ((_key?3017_ gx#stx-keyword?))
            (gx#stx-plist?__opt-lambda2930 _stx3015_ _key?3017_))))
      (define gx#stx-plist?
        (lambda _g4015_
          (let ((_g4014_ (length _g4015_)))
            (cond ((fx= _g4014_ 1) (apply gx#stx-plist?__0 _g4015_))
                  ((fx= _g4014_ 2)
                   (apply gx#stx-plist?__opt-lambda2930 _g4015_))
                  (else
                   (##raise-wrong-number-of-arguments-exception
                    gx#stx-plist?
                    _g4015_))))))))
  (begin
    (define gx#stx-getq__opt-lambda2848
      (lambda (_key2850_ _stx2851_ _key=?2852_)
        (let _lp2854_ ((_rest2856_ _stx2851_))
          (let* ((_g28572865_ (gx#syntax-e _rest2856_))
                 (_E28602869_
                  (lambda () (error '"No clause matching" _g28572865_)))
                 (_else28592873_ (lambda () '#f))
                 (_K28612907_
                  (lambda (_rest2876_ _hd2877_)
                    (let* ((_g28782885_ (gx#syntax-e _rest2876_))
                           (_E28802889_
                            (lambda ()
                              (error '"No clause matching" _g28782885_)))
                           (_K28812895_
                            (lambda (_rest2892_ _val2893_)
                              (if (_key=?2852_ _hd2877_ _key2850_)
                                  _val2893_
                                  (_lp2854_ _rest2892_)))))
                      (if (##pair? _g28782885_)
                          (let ((_hd28822898_ (##car _g28782885_))
                                (_tl28832900_ (##cdr _g28782885_)))
                            (let* ((_val2903_ _hd28822898_)
                                   (_rest2905_ _tl28832900_))
                              (_K28812895_ _rest2905_ _val2903_)))
                          (_E28802889_))))))
            (if (##pair? _g28572865_)
                (let ((_hd28622910_ (##car _g28572865_))
                      (_tl28632912_ (##cdr _g28572865_)))
                  (let* ((_hd2915_ _hd28622910_) (_rest2917_ _tl28632912_))
                    (_K28612907_ _rest2917_ _hd2915_)))
                (_else28592873_))))))
    (begin
      (define gx#stx-getq__0
        (lambda (_key2922_ _stx2923_)
          (let ((_key=?2925_ gx#stx-eq?))
            (gx#stx-getq__opt-lambda2848 _key2922_ _stx2923_ _key=?2925_))))
      (define gx#stx-getq
        (lambda _g4017_
          (let ((_g4016_ (length _g4017_)))
            (cond ((fx= _g4016_ 2) (apply gx#stx-getq__0 _g4017_))
                  ((fx= _g4016_ 3) (apply gx#stx-getq__opt-lambda2848 _g4017_))
                  (else
                   (##raise-wrong-number-of-arguments-exception
                    gx#stx-getq
                    _g4017_)))))))))
