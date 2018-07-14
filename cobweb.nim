
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

  HandlerProc* [E] = proc(event: Event[E])

  Observer* [E] = object
    dead: bool
    subscriptions: seq[HandlerProc[E]]

proc is_initial* [E](self: Event[E]): bool =
  return self.kind == etInitial

proc is_next* [E](self: Event[E]): bool =
  return self.kind == etNext

proc is_end* [E](self: Event[E]): bool =
  return self.kind == etEnd

proc is_error* [E](self: Event[E]): bool =
  return self.kind == etError

method dispatch*[E] (observer: Observer[E]; value: E) {.base.} =
  ## Sends an event to all subscribers of this observer.
  if observer.subscriptions == nil or observer.subscriptions.len < 1:
    # sanity check
    return

  # construct the event
  var event: Event[E]
  event.kind = etNext
  event.created_at = 0 # TODO get current system time
  event.value = value

  # transmit the event
  for s in observer.subscriptions:
    # TODO check return result; might have to remove subscribers
    s(event)

method on_subscription*[E] (observer: Observer[E]; fn: HandlerProc) {.base.} =
  ## Default observers don't react to new subscriptions.
  discard

proc subscribe*[E] (observer: var Observer[E]; handler: HandlerProc[E]) =
  ## Attaches a new handler to an existing observable. It
  ## will receive the raw event object for inspection.
  assert(handler != nil) # sanity test
  if observer.subscriptions == nil:
    # more sanity problems
    new_seq(observer.subscriptions, 0)

  observer.subscriptions.add(handler)
  on_subscription(observer, handler) # some streams care about this

proc sink*[E] (observer: Observer[E]): SinkProc[E] =
  ## Produces a sink closure. Calling this closure and
  ## providing an event is equivalent to calling dispatch
  ## on the observer itself.
  return proc(value: E): SinkResult =
    if observer.dead:
      return srNoMore
    else:
      observer.dispatch(value)
      if observer.dead:
        return srNoMore
      else:
        return srMore

when isMainModule:
  import unittest

  test "Sinking":
    var o: Observer[string]
    var target = false
    o.subscribe(proc (event: Event[string]) =
      target = true)
    var s = o.sink()
    check s("boo!") == srMore
    check target == true

