
import json
import tables

type
  CobwebBinding = object
    value: JsonNode

  Cobweb* = object
    values: Table[string, CobwebBinding]

proc make_cobweb*(): Cobweb =
  result.values = initTable[string, CobwebBinding]()

proc touch*(self: Cobweb; name: string) =
  ## Acts as though a variable has been changed, without actually changing it.  Used for complex situations.
  discard

proc `[]=`*(self: var Cobweb; name: string; value: JsonNode) =
  ## Sets a variable in the cobweb.  Notifies the dependency chain within the cobweb of a change.

  if self.values.haskey(name):
    var binding = self.values[name]
    binding.value = value
  else:
    self.values[name] = CobwebBinding(value: value)

  # TODO update chain

proc `[]`*(self: Cobweb; name: string): JsonNode =
  ## Retrieves a variable from the cobweb.
  try:
    result = self.values[name].value
  except KeyError:
    return nil
