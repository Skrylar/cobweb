
import json
import tables

type
  CobwebBinding = object
    value: JsonNode

  Cobweb* = object
    intern_table: Table[string, int]
    values: seq[CobwebBinding]

proc make_cobweb*(): Cobweb =
  result.intern_table = initTable[string, int]()
  newseq(result.values, 0)

proc intern(self: var Cobweb; name: string): int =
  ## Put in a name, get an identifier.  If the name is not known, create an identifier and return that.
  if self.intern_table.haskey(name):
    return self.intern_table[name]
  else:
    result = self.values.len
    self.intern_table[name] = result
    self.values.add(CobwebBinding(value: nil))

proc touch(self: var Cobweb; name: int) =
  discard

proc touch*(self: var Cobweb; name: string) =
  ## Acts as though a variable has been changed, without actually changing it.  Used for complex situations.
  if self.intern_table.haskey(name):
    self.touch self.intern_table[name]

proc `[]=`*(self: var Cobweb; name: string; value: JsonNode) =
  ## Sets a variable in the cobweb.  Notifies the dependency chain within the cobweb of a change.

  let id = self.intern(name)
  self.values[id].value = value
  self.touch id

proc `[]`*(self: Cobweb; name: string): JsonNode =
  ## Retrieves a variable from the cobweb.
  if self.intern_table.haskey(name):
    return self.values[self.intern_table[name]].value
  else:
    return nil
