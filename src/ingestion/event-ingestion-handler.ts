import { ReplicatedStorage,RunService } from "@rbxts/services"
import { UserConfig } from "../models/user-config.model"
import { EventRequest } from "../models/event.model"
import { EventBuilder } from "./event-builder"
import { RunTimeTypeEnforcement } from "./type-enforcement"
import { BatchHandler } from "../egress/components/batch-event-handler"

export class EventIngestionHandler {
  private serverEventStream?: BindableEvent 
  private clientEventStream: RemoteEvent 
  private userConfig: UserConfig
  private eventBuilder?: EventBuilder
  private batchHandler?: BatchHandler 
  private isServer: boolean 

  constructor(userConfig: UserConfig) {
    this.userConfig = userConfig

    this.isServer = RunService.IsServer()
    if (this.isServer) {
      this.serverEventConnections()
      this.serverEventStream = this.createServerEventStream()
      this.clientEventStream = this.createClientEventStream()
      this.eventBuilder = new EventBuilder(userConfig)
      this.batchHandler = new BatchHandler()
    }
    else {
      const remote = ReplicatedStorage.WaitForChild("RosaClientEventStream") as RemoteEvent
      this.clientEventStream = remote
    }
  }

  private serverEventConnections() {
    if (this.userConfig.clientEvents.enabled) {
      this.clientEventStream.OnServerEvent.Connect((
        player: Player, ...args: unknown[]
      ) => {
          if (!this.userConfig.clientEvents.enabled) {
            warn(`Client events are not enabled`)
            return
          }
          const event = args[0] as EventRequest
          if (this.userConfig.clientEvents.whitelistedEventTags) {
            if (!this.userConfig.clientEvents.whitelistedEventTags.includes(event.tag)) {
              warn(`${event.tag} is not a whitelisted client event.`)
            }
          }
          this.registerEvent(player, event)
      })
    }

    this.serverEventStream?.Event.Connect((player: Player, ...args: unknown[]) => {
      const event = args[0] as EventRequest
      print("Here")
      this.registerEvent(player, event)
    })
  }

  private registerEvent(player: Player, event: EventRequest): void {
    this.eventBuilder?.buildEvent(player, event).then((fullEvent) => {
      RunTimeTypeEnforcement.enforce(fullEvent)
      print("Here2")
      this.batchHandler?.addEvent(fullEvent)
    })
  }

  private createServerEventStream() {
    const bindable = new Instance("BindableEvent")
    bindable.Name = "ServerEventStream"
    return bindable
  }

  private createClientEventStream() {
    const remote = new Instance("RemoteEvent")
    remote.Name = "RosaClientEventStream"
    remote.Parent = ReplicatedStorage
    return remote
  }

  public addEvent(player: Player, event: EventRequest) {
    if (this.isServer) {
      this.serverEventStream?.Fire(player,event)
    }
    else {
      this.clientEventStream.FireServer(player,event)
    }
  }
}
