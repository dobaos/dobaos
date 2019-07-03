module errors;

// TODO: rethink
enum Errors {
  unknown = new Exception("ERR_UNKNOWN"),
  datapoint_not_found = new Exception("ERR_DATAPOINT_NOT_FOUND"),
  wrong_payload_type = new Exception("ERR_WRONG_PAYLOAD_TYPE"),
  wrong_payload = new Exception("ERR_WRONG_PAYLOAD"),
  datapoint_out_of_bounds = new Exception("ERR_DATAPOINT_OUT_OF_BOUNDS"),
  wrong_value_payload = new Exception("ERR_WRONG_VALUE_PAYLOAD"),
  baos_unknown = new Exception("ERR_BAOS_UNKNOWN"),
  baos_no_error = new Exception("ERR_BAOS_NO_ERROR"),
  baos_internal = new Exception("ERR_BAOS_INTERNAL"),
  baos_no_element_found = new Exception("ERR_BAOS_NO_ELEMENT_FOUND"),
  baos_buffer_too_small = new Exception("ERR_BAOS_BUFFER_TOO_SMALL"),
  baos_item_is_not_writeable = new Exception("ERR_BAOS_ITEM_NOT_WRITEABLE"),
  baos_service_not_supported = new Exception("ERR_BAOS_SERVICE_NOT_SUPPORTED"),
  baos_bad_service_parameter = new Exception("ERR_BAOS_BAD_SERVICE_PARAMETER"),
  baos_bad_id = new Exception("ERR_BAOS_BAD_ID"),
  baos_bad_command = new Exception("ERR_BAOS_BAD_COMMAND/VALUE"),
  baos_bad_length = new Exception("ERR_BAOS_BAD_LENGTH"),
  baos_message_inconsistent = new Exception("ERR_BAOS_MESSAGE_INCONSISTENT"),
  baos_busy = new Exception("ERR_BAOS_BUSY")
}

Exception BaosError(ubyte code) {
  switch(code) {
    case 0:
      return Errors.baos_no_error;
    case 1:
      return Errors.baos_internal;
    case 2:
      return Errors.baos_no_element_found;
    case 3:
      return Errors.baos_buffer_too_small;
    case 4:
      return Errors.baos_item_is_not_writeable;
    case 5:
      return Errors.baos_service_not_supported;
    case 6:
      return Errors.baos_bad_service_parameter;
    case 7:
      return Errors.baos_bad_id;
    case 8:
      return Errors.baos_bad_command;
    case 9:
      return Errors.baos_bad_length;
    case 10:
      return Errors.baos_message_inconsistent;
    case 11:
      return Errors.baos_busy;
    default:
      return Errors.baos_unknown;
  }
}
