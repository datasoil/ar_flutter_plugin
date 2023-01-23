package io.carius.lars.ar_flutter_plugin

import java.time.ZonedDateTime
import java.time.LocalDateTime
import kotlin.collections.ArrayList


internal class AnchorInfo(
    val id: String,
    //name: cod for Asset, title for Ticket
    val name: String,
    //type: "asset" for Asset, "ticket" for Ticket
    val type: String,
    val ts: String?,
    var ARanchorId: String?,
    var tickets: ArrayList<AnchorInfo>?
) {
    constructor(map: Map<String, Any>) : this(
        map["id"].toString(),
        map["name"].toString(),
        map["type"].toString(),
        if (map["ts"] != null) map["ts"].toString() else null,
        if (map["ar_anchor"] != null) map["ar_anchor"].toString() else null,
        if (map["tickets"] != null) ArrayList() else null
    ){
        if (map["tickets"] != null){
            val array = map["tickets"] as ArrayList<Map<String, Any>>;
            for (t in array){
                tickets!!.add(AnchorInfo(t))
            }
        }
    }

    @Override
    override fun toString(): String {
        return "AnchorInfo(id: $id, name: $name, type: $type, ar_anchor: ${ARanchorId}, tickets: ${tickets?.size.toString()})"
    }
}