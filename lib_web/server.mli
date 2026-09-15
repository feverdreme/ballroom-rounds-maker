open! Core

module For_testing : sig
  val callback
    :  app_js:string
    -> body:Cohttp_async.Body.t
    -> unit
    -> Cohttp.Request.t
    -> Cohttp_async.Server.response Async.Deferred.t
end

val command : Command.t
