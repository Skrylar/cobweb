
type
  EventType* = enum
    etInitial
    etNext
    etEnd
    etError

  SinkResult* = enum
    srMore   ## You can submit more events.
    srNoMore ## The stream is dead; you can't send more events.

  SinkProc* [E] = proc(value: E): SinkResult {.closure.}

  Event* [E] = object
    created_at*: int64
    case kind*: EventType
    of etInitial, etNext:
      value*: E
    of etError:
      error*: Exception
    of etEnd:
      discard

  HandlerResult* = enum
    hrMore   ## Remain subscribed.
    hrNoMore ## Remove me from your subscriptions.

  HandlerProc* [E] = proc(event: Event[E]): HandlerResult {.closure.}
  DoActionProc* [V] = proc(value: V) {.closure.}
  OnErrorProc* = proc(error: Exception) {.closure.}
  OnEndProc* = proc() {.closure.}
  FilterEventProc* [E] = proc(event: Event[E]): bool {.closure.}
  FilterValueProc* [V] = proc(value: V): bool {.closure.}
  MapEventProc* [E, R] = proc(event: Event[E]): R {.closure.}
  MapValueProc* [V, R] = proc(value: V): R {.closure.}

  ObserverFlag = enum
    ofDead

  Observer* [E] = ref object {.inheritable.}
    flags: set[ObserverFlag]
    subscriptions: seq[HandlerProc[E]]

  Property* [E] = ref object of Observer[E]
    current_value: E

proc is_initial* [E](self: Event[E]): bool =
  return self.kind == etInitial

proc is_next* [E](self: Event[E]): bool =
  return self.kind == etNext

proc is_end* [E](self: Event[E]): bool =
  return self.kind == etEnd

proc is_error* [E](self: Event[E]): bool =
  return self.kind == etError

proc dispatch*[E] (observer: Observer[E]; event: Event[E]) =
  ## Sends an event to all subscribers of this observer.
  template subs: untyped = observer.subscriptions
  if ofDead in observer.flags: return
  if subs == nil or subs.len < 1:
    # sanity check
    return

  # transmit the event
  var idx = 0
  while idx < subs.len:

    var s = subs[idx]
    case s(event)
    of hrMore:
      inc idx
    of hrNoMore:
      subs.delete(idx)

proc dispatch*[E] (observer: Observer[E]; value: E) =
  ## Sends an event to all subscribers of this observer.

  # construct the event
  var event: Event[E]
  event.kind = etNext
  event.created_at = 0 # TODO get current system time
  event.value = value

  observer.dispatch(event)

method on_subscription*[E] (observer: Observer[E]; fn: HandlerProc) {.base.} =
  ## Default observers don't react to new subscriptions.
  discard

proc subscribe*[E] (observer: Observer[E]; handler: HandlerProc[E]) =
  ## Attaches a new handler to an existing observable. It
  ## will receive the raw event object for inspection.
  assert(handler != nil) # sanity test
  if observer.subscriptions == nil:
    # more sanity problems
    new_seq(observer.subscriptions, 0)

  observer.subscriptions.add(handler)
  on_subscription(observer, handler) # some streams care about this

proc close*[E] (observer: Observer[E]) =
  ## Marks an observer as closed; an `end` event is
  ## dispatched and the observer is marked dead.

  # create final event
  var e: Event[E]
  e.kind = etEnd
  e.created_at = 0 # TODO

  # RIP
  observer.dispatch(e)
  incl observer.flags, ofDead

proc sink*[E] (observer: Observer[E]): SinkProc[E] =
  ## Produces a sink closure. Calling this closure and
  ## providing an event is equivalent to calling dispatch
  ## on the observer itself.
  return proc(value: E): SinkResult =
    if ofDead in observer.flags:
      return srNoMore
    else:
      observer.dispatch(value)
      if ofDead in observer.flags:
        return srNoMore
      else:
        return srMore

proc take* [E] (observer: Observer[E]; count: int): Observer[E] =
  ## Returns a new observer which will accept at most
  ## `count` values from this observer. Errors, initial
  ## values, and end of stream notifications are not counted.
  var output = new(Observer[E])
  var spuds = count
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.kind == etNext:
      dec spuds
      output.dispatch(event)

      if spuds < 1:
        output.close()
        return hrNoMore
    return hrMore)
  return output

proc take_until* [E, J] (observer: Observer[E]; observer2: Observer[J]): Observer[E] =
  var output = new(Observer[E])
  var fuse = false
  # subscription which will blow the fuse
  observer2.subscribe(proc (event: Event[J]): HandlerResult =
    if event.kind == etNext:
      fuse = true
      output.close()
      return hrNoMore
    else:
      return hrMore)
  # subscription to route events
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if fuse:
      return hrNoMore
    else:
      if event.kind == etEnd:
        output.close()
        return hrNoMore
      else
        output.dispatch(event)
        return hrMore)
  return output

proc do_action*[E] (observer: Observer[E]; fn: DoActionProc[E]): Observer[E] {.discardable.} =
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_next:
      fn(event.value)
    return hrMore)
  return observer

proc on_error*[E] (observer: Observer[E]; fn: OnErrorProc): Observer[E] {.discardable.} =
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_error:
      fn(event.error)
    return hrMore)
  return observer

proc on_end*[E] (observer: Observer[E]; fn: OnEndProc): Observer[E] {.discardable.} =
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_end:
      fn()
    return hrMore)
  return observer

proc keep*[E] (observer: Observer[E]; fn: FilterEventProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_next == true and fn(event) == true:
      dispatch[E](output, event)
    return hrMore)
  return output

proc keep*[E] (observer: Observer[E]; fn: FilterValueProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc(event: Event[E]): HandlerResult =
    case event.kind
    of etNext:
      if fn(event.value) == true:
        dispatch(output, event)
    of etError, etEnd:
        dispatch(output, event)
    of etInitial:
      discard
    return hrMore)
  return output

proc drop*[E] (observer: Observer[E]; fn: FilterEventProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_next == true and fn(event) == false:
      output.dispatch[E](event)
    return hrMore)
  return output

proc drop*[E] (observer: Observer[E]; fn: FilterValueProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    case event.kind
    of etNext:
      if fn(event.value) == false:
        dispatch(output, event)
    of etError, etEnd:
        dispatch(output, event)
    of etInitial:
      discard
    return hrMore)
  return output

proc map*[E, R] (observer: Observer[E]; fn: MapEventProc[E, R]): Observer[R] =
  var output = new(Observer[R])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    output.dispatch(fn(event))
    return hrMore)
  return output

proc map*[E, R] (observer: Observer[E]; fn: MapValueProc[E, R]): Observer[R] =
  var output = new(Observer[R])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    case event.kind
    of etNext:
      output.dispatch(fn(event.value))
    of etInitial:
      discard
    of etError, etEnd:
      output.dispatch(event)
    return hrMore)
  return output

proc map_error*[E, R] (observer: Observer[E];
                       fn: MapValueProc[Exception, R]): Observer[R] =
  ## Accepts errors that appear in the stream, and uses a
  ## `map` function to convert them in to another kind
  ## of event.
  var output = new(Observer[R])
  observer.subscribe(proc (event: Event[E]): HandlerResult =
    if event.is_error:
      output.dispatch(fn(event.error))
    return hrMore)
  return output

proc value* [E](property: Property): E {.inline.} =
  ## Returns the current value of a property.
  return property.current_value

proc `value=`* [E](property: Property[E]; new_value: E) {.inline.} =
  ## Sets the new value of a property, and updates subscribers.
  property.current_value = new_value
  property.dispatch(new_value)

when isMainModule:
  import unittest, math

  test "Sinking":
    var o = new(Observer[string])
    var target = false
    o.subscribe(proc (event: Event[string]): HandlerResult =
      target = true
      return hrMore)
    var s = o.sink()
    check s("boo!") == srMore
    check target == true

  test "Keeping events":
    var accumlator = 0
    var o = new(Observer[int])
    var filtered = o.keep(proc(input: int): bool = return input > 0)
    filtered.do_action proc(value: int) = inc accumlator, value

    check accumlator == 0
    o.dispatch(100)
    check accumlator == 100
    o.dispatch(-100)
    check accumlator == 100

  test "Mapping events":
    var accumlator = 0
    var o = new(Observer[int])
    var mapped = o.map(proc(input: int): int = return abs(input))
    mapped.do_action proc(value: int) = inc accumlator, value

    check accumlator == 0
    o.dispatch(100)
    check accumlator == 100
    o.dispatch(-100)
    check accumlator == 200

  test "Property subscription":
    var prop = new(Property[int])
    var target = 0

    prop.do_action do(value: int):
      target = value

    prop.value = 42
    check target == 42

