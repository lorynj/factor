! Copyright (C) 2005, 2008 Slava Pestov.
! See http://factorcode.org/license.txt for BSD license.
USING: arrays definitions hashtables kernel
kernel.private math namespaces sequences sequences.private
strings vectors words quotations memory combinators generic
classes classes.private slots.deprecated slots.private slots
compiler.units math.private accessors assocs ;
IN: classes.tuple

M: tuple class 1 slot 2 slot { word } declare ;

ERROR: not-a-tuple object ;

: check-tuple ( object -- tuple )
    dup tuple? [ not-a-tuple ] unless ; inline

<PRIVATE

: tuple-layout ( class -- layout )
    "layout" word-prop ;

: layout-of ( tuple -- layout )
    1 slot { tuple-layout } declare ; inline

: tuple-size ( tuple -- size )
    layout-of size>> ; inline

: prepare-tuple>array ( tuple -- n tuple layout )
    check-tuple [ tuple-size ] [ ] [ layout-of ] tri ;

: copy-tuple-slots ( n tuple -- array )
    [ array-nth ] curry map ;

PRIVATE>

: tuple>array ( tuple -- array )
    prepare-tuple>array
    >r copy-tuple-slots r>
    class>> prefix ;

: tuple-slots ( tuple -- seq )
    prepare-tuple>array drop copy-tuple-slots ;

: all-slots ( class -- slots )
    superclasses [ "slots" word-prop ] map concat ;

: check-slots ( seq class -- seq class )
    [ ] [
        2dup all-slots [
            class>> 2dup instance?
            [ 2drop ] [ bad-slot-value ] if
        ] 2each
    ] if-bootstrapping ; inline

: slots>tuple ( seq class -- tuple )
    check-slots
    new [
        [ tuple-size ]
        [ [ set-array-nth ] curry ]
        bi 2each
    ] keep ;

: >tuple ( seq -- tuple )
    unclip slots>tuple ;

: slot-names ( class -- seq )
    "slot-names" word-prop ;

: all-slot-names ( class -- slots )
    superclasses [ slot-names ] map concat \ class prefix ;

ERROR: bad-superclass class ;

<PRIVATE

: tuple= ( tuple1 tuple2 -- ? )
    2dup [ layout-of ] bi@ eq? [
        [ drop tuple-size ]
        [ [ [ drop array-nth ] [ nip array-nth ] 3bi = ] 2curry ]
        2bi all-integers?
    ] [
        2drop f
    ] if ; inline

: tuple-instance? ( object class echelon -- ? )
    #! 4 slot == superclasses>>
    rot dup tuple? [
        layout-of 4 slot
        2dup array-capacity fixnum<
        [ array-nth eq? ] [ 3drop f ] if
    ] [ 3drop f ] if ; inline

: define-tuple-predicate ( class -- )
    dup dup tuple-layout echelon>>
    [ tuple-instance? ] 2curry define-predicate ;

: superclass-size ( class -- n )
    superclasses but-last-slice
    [ slot-names length ] map sum ;

: (instance-check-quot) ( class -- quot )
    [
        \ dup ,
        [ "predicate" word-prop % ]
        [ [ bad-slot-value ] curry , ] bi
        \ unless ,
    ] [ ] make ;

: instance-check-quot ( class -- quot )
    {
        { [ dup object bootstrap-word eq? ] [ drop [ ] ] }
        { [ dup "coercer" word-prop ] [ "coercer" word-prop ] }
        [ (instance-check-quot) ]
    } cond ;

: boa-check-quot ( class -- quot )
    all-slots 1 tail [ class>> instance-check-quot ] map spread>quot ;

: define-boa-check ( class -- )
    dup boa-check-quot "boa-check" set-word-prop ;

: generate-tuple-slots ( class slots -- slot-specs )
    over superclass-size 2 + make-slots deprecated-slots ;

: define-tuple-slots ( class -- )
    dup dup "slot-names" word-prop generate-tuple-slots
    [ "slots" set-word-prop ]
    [ define-accessors ] ! new
    [ define-slots ] ! old
    2tri ;

: make-tuple-layout ( class -- layout )
    [ ]
    [ [ superclass-size ] [ slot-names length ] bi + ]
    [ superclasses dup length 1- ] tri
    <tuple-layout> ;

: define-tuple-layout ( class -- )
    dup make-tuple-layout "layout" set-word-prop ;

: compute-slot-permutation ( class old-slot-names -- permutation )
    >r all-slot-names r> [ index ] curry map ;

: apply-slot-permutation ( old-values permutation -- new-values )
    [ [ swap ?nth ] [ drop f ] if* ] with map ;

: permute-slots ( old-values -- new-values )
    dup first dup outdated-tuples get at
    compute-slot-permutation
    apply-slot-permutation ;

: change-tuple ( tuple quot -- newtuple )
    >r tuple>array r> call >tuple ; inline

: update-tuple ( tuple -- newtuple )
    [ permute-slots ] change-tuple ;

: update-tuples ( -- )
    outdated-tuples get
    dup assoc-empty? [ drop ] [
        [ >r class r> key? ] curry instances
        dup [ update-tuple ] map become
    ] if ;

[ update-tuples ] update-tuples-hook set-global

: update-tuples-after ( class -- )
    outdated-tuples get [ all-slot-names ] cache drop ;

M: tuple-class update-class
    {
        [ define-tuple-layout ]
        [ define-tuple-slots ]
        [ define-tuple-predicate ]
        [ define-boa-check ]
    } cleave ;

: define-new-tuple-class ( class superclass slots -- )
    [ drop f f tuple-class define-class ]
    [ nip "slot-names" set-word-prop ]
    [ 2drop update-classes ]
    3tri ;

: subclasses ( class -- classes )
    class-usages [ tuple-class? ] filter ;

: each-subclass ( class quot -- )
    >r subclasses r> each ; inline

: redefine-tuple-class ( class superclass slots -- )
    [
        2drop
        [
            [ update-tuples-after ]
            [ +inlined+ changed-definition ]
            [ redefined ]
            tri
        ] each-subclass
    ]
    [ define-new-tuple-class ]
    3bi ;

: tuple-class-unchanged? ( class superclass slots -- ? )
    rot tuck [ superclass = ] [ slot-names = ] 2bi* and ;

: valid-superclass? ( class -- ? )
    [ tuple-class? ] [ tuple eq? ] bi or ;

: check-superclass ( superclass -- )
    dup valid-superclass? [ bad-superclass ] unless drop ;

PRIVATE>

GENERIC# define-tuple-class 2 ( class superclass slots -- )

M: word define-tuple-class
    over check-superclass
    define-new-tuple-class ;

M: tuple-class define-tuple-class
    3dup tuple-class-unchanged?
    [ over check-superclass 3dup redefine-tuple-class ] unless
    3drop ;

: define-error-class ( class superclass slots -- )
    [ define-tuple-class ] [ 2drop ] 3bi
    dup [ boa throw ] curry define ;

M: tuple-class reset-class
    [
        dup "slots" word-prop [
            name>>
            [ reader-word method forget ]
            [ writer-word method forget ] 2bi
        ] with each
    ] [
        [ call-next-method ]
        [ { "layout" "slots" "slot-names" } reset-props ]
        bi
    ] bi ;

M: tuple-class rank-class drop 0 ;

M: tuple-class instance?
    dup tuple-layout echelon>> tuple-instance? ;

M: tuple clone
    (clone) dup delegate clone over set-delegate ;

M: tuple equal?
    over tuple? [ tuple= ] [ 2drop f ] if ;

M: tuple hashcode*
    [
        [ class hashcode ] [ tuple-size ] [ ] tri
        >r rot r> [
            swapd array-nth hashcode* sequence-hashcode-step
        ] 2curry each
    ] recursive-hashcode ;

M: tuple-class new tuple-layout <tuple> ;

M: tuple-class boa
    [ "boa-check" word-prop call ]
    [ tuple-layout ]
    bi <tuple-boa> ;

! Deprecated
M: object get-slots ( obj slots -- ... )
    [ execute ] with each ;

M: object set-slots ( ... obj slots -- )
    <reversed> get-slots ;

: delegates ( obj -- seq ) [ delegate ] follow ;

: is? ( obj quot -- ? ) >r delegates r> contains? ; inline
