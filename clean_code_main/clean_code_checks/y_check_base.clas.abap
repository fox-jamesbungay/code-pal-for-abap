CLASS y_check_base DEFINITION ABSTRACT
  PUBLIC
  INHERITING FROM cl_ci_test_scan
  CREATE PUBLIC .

  PUBLIC SECTION.

    CONSTANTS:
      BEGIN OF c_code,
        error        TYPE sci_errc VALUE '100',
        warning      TYPE sci_errc VALUE '101',
        notification TYPE sci_errc VALUE '102',
      END OF c_code .
    DATA:
      BEGIN OF settings READ-ONLY,
        pseudo_comment                TYPE sci_pcom,
        disable_on_prodcode_selection TYPE abap_bool,
        disable_on_testcode_selection TYPE abap_bool,
        disable_threshold_selection   TYPE abap_bool,
        object_created_on             TYPE creationdt,
        threshold                     TYPE ycicc_threshold,
        prio                          TYPE ycicc_message_kind,
        apply_on_productive_code      TYPE ycicc_productive_code,
        apply_on_test_code            TYPE ycicc_testcode,
        documentation                 TYPE c LENGTH 1000,
      END OF settings .

    METHODS constructor .

    METHODS get_attributes
        REDEFINITION .
    METHODS if_ci_test~display_documentation
        REDEFINITION .
    METHODS if_ci_test~query_attributes
        REDEFINITION .
    METHODS put_attributes
        REDEFINITION .
    METHODS run
        REDEFINITION .
  PROTECTED SECTION.

    DATA check_configurations TYPE y_if_clean_code_manager=>check_configurations .
    DATA check_name TYPE seoclsname .
    DATA clean_code_exemption_handler TYPE REF TO y_exemption_handler .
    DATA clean_code_manager TYPE REF TO y_if_clean_code_manager .
    DATA is_testcode TYPE abap_bool .
    DATA ref_scan_manager TYPE REF TO y_if_scan_manager .
    DATA statement_for_message TYPE sstmnt .
    DATA statistics TYPE REF TO y_if_scan_statistics .
    DATA test_code_detector TYPE REF TO y_if_testcode_detector .
    DATA use_default_attributes TYPE abap_bool VALUE abap_true ##NO_TEXT.
    DATA attributes_maintained TYPE abap_bool .

    METHODS check_start_conditions
      RAISING
        ycx_object_not_processed
        ycx_object_is_exempted .
    METHODS detect_check_configuration
      IMPORTING
        !threshold    TYPE int4
        !include      TYPE sobj_name
      RETURNING
        VALUE(result) TYPE y_if_clean_code_manager=>check_configuration .
    METHODS execute_check .
    METHODS get_code
      IMPORTING
        !message_prio TYPE sychar01
      RETURNING
        VALUE(result) TYPE sci_errc .
    METHODS inspect_tokens
      ABSTRACT
      IMPORTING
        !structure TYPE sstruc OPTIONAL
        !index     TYPE i OPTIONAL
        !statement TYPE sstmnt OPTIONAL .
    METHODS raise_error
      IMPORTING
        !p_sub_obj_type TYPE trobjtype
        !p_level        TYPE stmnt_levl
        !p_position     TYPE int4
        !p_from         TYPE int4
        !p_errcnt       TYPE sci_errcnt OPTIONAL
        VALUE(p_kind)   TYPE sychar01
        !p_test         TYPE sci_chk
        !p_code         TYPE sci_errc
        !p_suppress     TYPE sci_pcom OPTIONAL
        !p_param_1      TYPE csequence OPTIONAL
        !p_param_2      TYPE csequence OPTIONAL
        !p_param_3      TYPE csequence OPTIONAL
        !p_param_4      TYPE csequence OPTIONAL
        !p_inclspec     TYPE sci_inclspec DEFAULT ' '
        !p_detail       TYPE xstring OPTIONAL
        !p_checksum_1   TYPE int4 OPTIONAL
        !p_comments     TYPE t_comments OPTIONAL .

    METHODS get_column_abs
        REDEFINITION .
    METHODS get_column_rel
        REDEFINITION .
    METHODS get_include
        REDEFINITION .
    METHODS get_line_abs
        REDEFINITION .
    METHODS get_line_column_abs
        REDEFINITION .
    METHODS get_line_column_rel
        REDEFINITION .
    METHODS get_line_rel
        REDEFINITION .
    METHODS get_token_abs
        REDEFINITION .
    METHODS get_token_rel
        REDEFINITION .
    METHODS keyword
        REDEFINITION .
  PRIVATE SECTION.
    METHODS do_attributes_exist
      RETURNING
        VALUE(result) TYPE abap_bool .
    METHODS instantiate_objects .
ENDCLASS.



CLASS Y_CHECK_BASE IMPLEMENTATION.


  METHOD check_start_conditions.
    IF ref_scan_manager->is_scan_ok( ) = abap_false.
      RAISE EXCEPTION TYPE ycx_object_not_processed.
    ENDIF.

    IF clean_code_exemption_handler->is_object_exempted( object_name = object_name object_type = object_type ) = abap_true.
      RAISE EXCEPTION TYPE ycx_object_is_exempted.
    ENDIF.
  ENDMETHOD.


  METHOD constructor.
    super->constructor( ).

    settings-object_created_on = '20160101'.
    settings-prio = 'E'.
    settings-threshold = 5.
    settings-apply_on_productive_code = abap_true.
    settings-apply_on_test_code = abap_true.
    settings-documentation = 'https://github.com/SAP/code-pal-for-abap/blob/master/docs/check_documentation.md' ##NO_TEXT.

    has_attributes = do_attributes_exist( ).

    INSERT VALUE #( test = me->myname
                    code = '104'
                    kind = cl_ci_test_root=>c_note
                    text = 'Check not customized!'(104) ) INTO TABLE me->scimessages[].

    INSERT VALUE #( test = me->myname
                    code = '105'
                    kind = cl_ci_test_root=>c_note
                    text = 'Object exempted - E.g. Object is generated'(105) ) INTO TABLE me->scimessages[].

    INSERT VALUE #( test = me->myname
                    code = '106'
                    kind = cl_ci_test_root=>c_note
                    text = 'Maintain Attributes for the Code Inspector Check!'(106) ) INTO TABLE me->scimessages[].
  ENDMETHOD.


  METHOD detect_check_configuration.
    DATA config TYPE y_if_clean_code_manager=>check_configuration.

    DATA(object_creation_date) = NEW y_object_creation_date( ).
    DATA(crt_date) = object_creation_date->y_if_object_creation_date~get_program_create_date( include ).

    LOOP AT check_configurations INTO config
      WHERE object_creation_date LE crt_date AND
            threshold LE threshold.

      IF is_testcode = abap_true AND config-apply_on_testcode = abap_false.
        CONTINUE.
      ELSEIF is_testcode = abap_false AND config-apply_on_productive_code = abap_false.
        CONTINUE.
      ENDIF.

      IF result IS INITIAL.
        result = config.

      ELSEIF result-prio = config-prio AND
           result-threshold GE config-threshold.
        result = config.

      ELSEIF result-threshold LE config-threshold AND
             ( ( result-prio = 'W' AND config-prio = 'E' ) OR
               ( result-prio = 'N' AND config-prio = 'E' ) OR
               ( result-prio = 'N' AND config-prio = 'W' ) ).
        result = config.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD do_attributes_exist.
    DATA profile_manager TYPE REF TO object.
    DATA profiles_ref TYPE REF TO data.
    FIELD-SYMBOLS <profiles> TYPE ANY TABLE.

    TRY.
        CREATE DATA profiles_ref TYPE STANDARD TABLE OF (`YTAB_PROFILES`) WITH DEFAULT KEY.
        ASSIGN profiles_ref->* TO <profiles>.

        CREATE OBJECT profile_manager TYPE (`Y_PROFILE_MANAGER`).

        DATA(ptab) = VALUE abap_parmbind_tab( ( name  = 'USERNAME'
                                                kind  = cl_abap_objectdescr=>exporting
                                                value = REF #( sy-uname ) )
                                              ( name  = 'RESULT'
                                                kind  = cl_abap_objectdescr=>returning
                                                value = REF #( <profiles> ) ) ).

        CALL METHOD profile_manager->('Y_IF_PROFILE_MANAGER~SELECT_PROFILES')
          PARAMETER-TABLE ptab.

        IF <profiles> IS NOT ASSIGNED.
          RETURN.
        ENDIF.

        IF lines( <profiles> ) > 0.
          result = abap_false.
        ELSE.
          result = abap_true.
        ENDIF.

      CATCH cx_sy_create_data_error
            cx_sy_create_object_error
            ycx_entry_not_found.
        result = abap_true.
    ENDTRY.
  ENDMETHOD.


  METHOD execute_check.
    LOOP AT ref_scan_manager->get_structures( ) ASSIGNING FIELD-SYMBOL(<structure>)
       WHERE stmnt_type EQ scan_struc_stmnt_type-form
          OR stmnt_type EQ scan_struc_stmnt_type-method
          OR stmnt_type EQ scan_struc_stmnt_type-function
          OR stmnt_type EQ scan_struc_stmnt_type-module
          OR type EQ scan_struc_type-event.

      is_testcode = test_code_detector->is_testcode( <structure> ).

      TRY.
          DATA(check_configuration) = check_configurations[ apply_on_testcode = abap_true ].
        CATCH cx_sy_itab_line_not_found.
          IF is_testcode EQ abap_true.
            CONTINUE.
          ENDIF.
      ENDTRY.

      DATA(index) = <structure>-stmnt_from.

      LOOP AT ref_scan_manager->get_statements( ) ASSIGNING FIELD-SYMBOL(<statement>)
        FROM <structure>-stmnt_from TO <structure>-stmnt_to.

        inspect_tokens( index = index
                        structure = <structure>
                        statement = <statement> ).
        index = index + 1.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_attributes.
    READ TABLE check_configurations INTO DATA(check_configuration) INDEX 1.
    EXPORT
      object_creation_date = check_configuration-object_creation_date
      message_severity = check_configuration-prio
      threshold = check_configuration-threshold
      apply_on_productive_code = check_configuration-apply_on_productive_code
      apply_on_testcode = check_configuration-apply_on_testcode
    TO DATA BUFFER p_attributes.
  ENDMETHOD.


  METHOD get_code.
    CASE message_prio.
      WHEN c_error.
        result = c_code-error.
      WHEN c_warning.
        result = c_code-warning.
      WHEN c_note.
        result = c_code-notification.
    ENDCASE.
  ENDMETHOD.


  METHOD get_column_abs.
    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    DO.
      READ TABLE tokens INDEX p_n ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_result = <token>-col.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM p_n.
    ENDDO.
  ENDMETHOD.


  METHOD get_column_rel.
    DATA(index) = statement_wa-from + p_n - 1.
    CHECK index <= statement_wa-to.

    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    DO.
      READ TABLE tokens INDEX index ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_result = <token>-col.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM index.
    ENDDO.
  ENDMETHOD.


  METHOD get_include.
    DATA:
      l_levels_wa LIKE LINE OF ref_scan->levels,
      l_level     TYPE i.

    IF p_level IS SUPPLIED.
      l_level = p_level.
    ELSE.
      l_level = statement_wa-level.
    ENDIF.
    DO.
      READ TABLE ref_scan_manager->get_levels( ) INDEX l_level INTO l_levels_wa.
      IF sy-subrc NE 0.
        RETURN.
      ENDIF.
      IF l_levels_wa-type = 'P'.
        p_result = l_levels_wa-name.
        RETURN.
      ENDIF.
      l_level = l_levels_wa-level.
    ENDDO.
  ENDMETHOD.


  METHOD get_line_abs.
    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    DO.
      READ TABLE tokens INDEX p_n ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_result = <token>-row.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM p_n.
    ENDDO.
  ENDMETHOD.


  METHOD get_line_column_abs.
    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    DO.
      READ TABLE tokens INDEX p_n ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_column = <token>-col.
        p_line   = <token>-row.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM p_n.
    ENDDO.
  ENDMETHOD.


  METHOD get_line_column_rel.
    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    p_n = statement_wa-from + p_n - 1.

    DO.
      READ TABLE tokens INDEX p_n ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_column = <token>-col.
        p_line   = <token>-row.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM p_n.
    ENDDO.
  ENDMETHOD.


  METHOD get_line_rel.
    DATA(index) = statement_wa-from + p_n - 1.
    CHECK index <= statement_wa-to.

    DATA(tokens) = ref_scan_manager->get_tokens( ).
    IF lines( tokens ) = 0.
      RETURN.
    ENDIF.

    DO.
      READ TABLE tokens INDEX index ASSIGNING FIELD-SYMBOL(<token>).
      IF sy-subrc EQ 0 AND <token>-row <> 0.
        p_result = <token>-row.
        RETURN.
      ENDIF.
      SUBTRACT 1 FROM index.
    ENDDO.
  ENDMETHOD.


  METHOD get_token_abs.
    READ TABLE ref_scan_manager->get_tokens( ) INDEX p_n INTO token_wa.
    IF sy-subrc EQ 0.
      p_result = token_wa-str.
    ENDIF.
  ENDMETHOD.


  METHOD get_token_rel.
    DATA: l_index TYPE i.

    l_index = statement_wa-from + p_n - 1.
    IF l_index > statement_wa-to.
      RETURN.
    ENDIF.
    READ TABLE ref_scan_manager->get_tokens( ) INDEX l_index INTO token_wa.
    p_result = token_wa-str.
  ENDMETHOD.


  METHOD if_ci_test~display_documentation.
    CALL FUNCTION 'CALL_BROWSER'
      EXPORTING
        url                    = settings-documentation
        window_name            = ' '
        new_window             = 'X'
      EXCEPTIONS
        frontend_not_supported = 1
        frontend_error         = 2
        prog_not_found         = 3
        no_batch               = 4
        unspecified_error      = 5
        OTHERS                 = 6.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.
  ENDMETHOD.


  METHOD if_ci_test~query_attributes.
    DATA sci_attributes TYPE sci_atttab.
    DATA title(75) TYPE c.
    DATA message(72) TYPE c.

    READ TABLE check_configurations INTO DATA(check_configuration) INDEX 1.

    IF use_default_attributes EQ abap_true.
      check_configuration-object_creation_date = settings-object_created_on.
      check_configuration-prio = settings-prio.
      check_configuration-apply_on_productive_code = settings-apply_on_productive_code.
      check_configuration-apply_on_testcode = settings-apply_on_test_code.
      check_configuration-threshold = settings-threshold.
    ENDIF.

    INSERT VALUE #(
      kind = ''
      ref  = REF #( check_configuration-object_creation_date )
      text =  'Consider Objects created after'(200)
    ) INTO TABLE sci_attributes.

    INSERT VALUE #(
      kind = ''
      ref  = REF #( check_configuration-prio )
      text =  'Message Severity'(201)
    ) INTO TABLE sci_attributes.

    IF settings-disable_threshold_selection = abap_false.
      INSERT VALUE #(
        kind = ''
        ref  = REF #( check_configuration-threshold )
        text =  'Threshold'(203)
      ) INTO TABLE sci_attributes.
    ENDIF.

    IF settings-disable_on_prodcode_selection = abap_false.
      INSERT VALUE #(
        kind = ''
        ref  = REF #( check_configuration-apply_on_productive_code )
        text =  'Apply on Productive Code'(204)
      ) INTO TABLE sci_attributes.
    ENDIF.

    IF settings-disable_on_testcode_selection = abap_false.
      INSERT VALUE #(
        kind = ''
        ref  = REF #( check_configuration-apply_on_testcode )
        text =  'Apply on Testcode'(202)
      ) INTO TABLE sci_attributes.
    ENDIF.

    title = description.

    attributes_ok = abap_false.
    WHILE attributes_ok = abap_false.
      IF cl_ci_query_attributes=>generic(
                         p_name       = name
                         p_title      = title
                         p_attributes = sci_attributes
                         p_message    = message
                         p_display    = p_display ) = abap_true.
        attributes_ok = abap_true.
        RETURN.
      ENDIF.
      IF check_configuration-apply_on_productive_code = abap_false AND
         check_configuration-apply_on_testcode        = abap_false.
        message = 'Choose the Type of Code to be checked'(300).
      ELSEIF check_configuration-prio IS INITIAL.
        message = 'Choose a Message Severity'(301).
      ELSE.
        IF check_configuration-object_creation_date = '00000000'.
          check_configuration-object_creation_date = '19000101'.
        ENDIF.

        attributes_ok = abap_true.
      ENDIF.
    ENDWHILE.

    CLEAR check_configurations.
    APPEND check_configuration TO check_configurations.
    use_default_attributes = abap_false.
  ENDMETHOD.


  METHOD instantiate_objects.
    IF ref_scan_manager IS NOT BOUND.
      ref_scan_manager = NEW lcl_ref_scan_manager( ).
      IF ref_scan IS INITIAL.
        get( ).
      ENDIF.
    ENDIF.
    ref_scan_manager->set_ref_scan( ref_scan ).

    IF clean_code_manager IS NOT BOUND.
      clean_code_manager = NEW y_clean_code_manager( ).
    ENDIF.

    IF clean_code_exemption_handler IS NOT BOUND.
      clean_code_exemption_handler = NEW y_exemption_handler( ).
    ENDIF.

    IF test_code_detector IS NOT BOUND.
      test_code_detector = NEW lcl_test_code_detector( ).
    ENDIF.
    test_code_detector->clear( ).
    test_code_detector->set_ref_scan_manager( ref_scan_manager ).

    IF statistics IS NOT BOUND.
      statistics = NEW lcl_statistics( ).
    ENDIF.

    IF lines( check_configurations ) = 1 AND
       check_configurations[ 1 ]-object_creation_date = '00000000'.
      CLEAR check_configurations.
    ENDIF.
  ENDMETHOD.


  METHOD keyword.
    IF statement_wa-type = 'C'.
      p_result = 'COMPUTE'.
      RETURN.
    ENDIF.
    READ TABLE ref_scan_manager->get_tokens( ) INDEX statement_wa-from INTO token_wa.
    p_result = token_wa-str.
  ENDMETHOD.


  METHOD put_attributes.
    DATA check_configuration TYPE y_if_clean_code_manager=>check_configuration.

    attributes_maintained = abap_true.
    TRY.
        IMPORT
          object_creation_date = check_configuration-object_creation_date
          message_severity = check_configuration-prio
          threshold = check_configuration-threshold
          apply_on_productive_code = check_configuration-apply_on_productive_code
          apply_on_testcode = check_configuration-apply_on_testcode
        FROM DATA BUFFER p_attributes.
        APPEND check_configuration TO check_configurations.
      CATCH cx_root.
        attributes_maintained = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD raise_error.
    statistics->collect( kind = p_kind
                         pc = NEW lcl_pseudo_comment_detector( )->lif_pseudo_comment_detector~is_pseudo_comment( ref_scan_manager = ref_scan_manager
                                                                                                                 scimessages      = scimessages
                                                                                                                 test             = p_test
                                                                                                                 code             = p_code
                                                                                                                 suppress         = p_suppress
                                                                                                                 position         = p_position ) ).
    IF cl_abap_typedescr=>describe_by_object_ref( ref_scan_manager )->get_relative_name( ) EQ 'LCL_REF_SCAN_MANAGER'.
      inform( p_sub_obj_type = p_sub_obj_type
              p_sub_obj_name = get_include( p_level = p_level )
              p_position = p_position
              p_line = get_line_abs( p_from )
              p_column = get_column_abs( p_from )
              p_errcnt = p_errcnt
              p_kind = p_kind
              p_test = p_test
              p_code = p_code
              p_suppress = p_suppress
              p_param_1 = p_param_1
              p_param_2 = p_param_2
              p_param_3 = p_param_3
              p_param_4 = p_param_4
              p_inclspec = p_inclspec
              p_detail = p_detail
              p_checksum_1 = p_checksum_1
              p_comments = p_comments ).
    ENDIF.
  ENDMETHOD.


  METHOD run.
    instantiate_objects( ).

    IF attributes_maintained = abap_false AND has_attributes = abap_true.
      raise_error(
        EXPORTING
          p_sub_obj_type    = c_type_include
          p_level           = 1
          p_position        = 1
          p_from            = 1
          p_kind            = ''
          p_test            = me->myname
          p_code            = '106' ).
      RETURN.
    ENDIF.

    TRY.
        check_start_conditions( ).
      CATCH ycx_object_not_processed.
        RETURN.

      CATCH ycx_object_is_exempted.
*        raise_error(
*          EXPORTING
*              p_sub_obj_type    = c_type_include
*              p_level           = 1
*              p_position        = 1
*              p_from            = 1
*              p_kind            = ''
*              p_test            = me->myname
*              p_code            = '105' ).
        RETURN.
    ENDTRY.

    TRY.
        DATA(profile_configurations) = clean_code_manager->read_check_customizing( username    = sy-uname
                                                                                   checkid     = myname
                                                                                   object_name = object_name
                                                                                   object_type = object_type ).
      CATCH ycx_no_check_customizing.
        IF lines( check_configurations ) = 0.
*          raise_error(
*            EXPORTING
*              p_sub_obj_type    = c_type_include
*              p_level           = 1
*              p_position        = 1
*              p_from            = 1
*              p_kind            = ''
*              p_test            = me->myname
*              p_code            = '104' ).
          RETURN.
        ENDIF.
    ENDTRY.

    IF lines( check_configurations ) > 0.
      DELETE check_configurations WHERE object_creation_date > clean_code_manager->calculate_obj_creation_date( object_name = object_name
                                                                                                                object_type = object_type ).
    ENDIF.

    IF lines( profile_configurations ) > 0.
      check_configurations = profile_configurations.
    ENDIF.

    execute_check( ).

    FREE ref_scan_manager.
  ENDMETHOD.
ENDCLASS.
