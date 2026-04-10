import { HttpService } from "@rbxts/services";
import { Accumulator } from "./accumulator";
import { CompressionHandler } from "./compressor";
import { splitArrayInHalf } from "../utils/array-manipulation";
import { Signature } from "./signature";
import { sendRetryHandler } from "../utils/api.utils";
import { EVENTS_API_ROUTE } from "../models/constants.model";
import { Event } from "../../models/event.model";

let handler: BatchHandler

export class BatchHandler {
  private accumulator = new Accumulator()

  constructor() {
    if (handler) {
      throw 'Only one instance of BatchHandler is allowed'
    }
    handler = this
  }

  public addEvent(event: Event) {
    const [isValid, err] = this.typeEnforcer(event)
    print("TEsting")
    if (!isValid) {
      throw `Invalid event: ${err}`
    }
    const readyToFlush = this.accumulator.addEvent(event)
    if (readyToFlush) {
      this.sendEventBuffer(this.accumulator.flushEvents())
    }
  }

  private sendEventBuffer(buff: buffer) {
    const compressedBuffer = CompressionHandler.compress(buff)
    if (!compressedBuffer) {
      this.splitEventsAndFlush(buff)
      return
    }
    const headers = Signature.generateHeader()
    const requestData: RequestAsyncRequest = {
        Url: EVENTS_API_ROUTE,
        Method: "POST",
        Body: buffer.tostring(compressedBuffer),
        Headers: headers
    }
    new Promise<[RequestAsyncResponse, number]>((resolve) => {
      resolve(sendRetryHandler(requestData))
    }).then(([response, retryCount]) => {
        if (!response.Success) {
          const prefix = 'ROSA API request failed with status code'
          const suffix = `: ${response.StatusCode} after ${retryCount} attempts`
          const rawError = `\n${response.StatusMessage}\n${response.Body}`
          throw `${prefix}${suffix}${rawError}`
        }
        if (retryCount > 1) {
          warn(`ROSA API request succeeded after ${retryCount} attempts`)
        }
    })
  }

  private splitEventsAndFlush(buff: buffer) {
    const stringifiedBuffer = buffer.readstring(buff,0,buffer.len(buff))
    const events: Event[] = HttpService.JSONDecode(stringifiedBuffer) as Event[]
    const [halfA, halfB] = splitArrayInHalf(events)
    this.sendEventBuffer(buffer.fromstring(HttpService.JSONEncode(halfA)))
    this.sendEventBuffer(buffer.fromstring(HttpService.JSONEncode(halfB)))
  }

  private typeEnforcer(event: Event): [true] | [false, string] {
    return [true]
  } 
}
