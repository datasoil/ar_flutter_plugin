package io.carius.lars.ar_flutter_plugin

import java.time.ZonedDateTime
import java.time.LocalDateTime
import kotlin.collections.ArrayList

internal class BFunction(
    _id: String,
    _cod: String,
    _name: String,
    _color: String?
) {
    val id: String = _id
    val color: String? = _color
    val name: String = _name
    val cod: String = _cod

    constructor (map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["cod"].toString(),
                map["name"].toString(),
                if (map["color"] != null) map["color"].toString() else null
            ) {
    }
}

internal class Category(
    _id: String,
    _cod: String,
    _name: String
) {
    val id: String = _id
    val name: String = _name
    val cod: String = _cod

    constructor (map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["name"].toString(),
                map["cod"].toString()
            ) {
    }
}

internal class SynTicket(
    _id: String,
    _title: String,
    _time: LocalDateTime
) {
    val id: String = _id
    val title: String = _title
    val ts: LocalDateTime = _time


    constructor(map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["title"].toString(),
                (ZonedDateTime.parse(map["ts"].toString())).toLocalDateTime()
            ) {
    }


    @Override
    override fun toString(): String {
        val formatter: java.time.format.DateTimeFormatter =
            java.time.format.DateTimeFormatter.ofPattern("dd/MM - HH:mm");
        return ts.format(formatter) + " - " + title;
    }
}

internal class SynEvent(
    _id: String,
    _title: String,
    _time: LocalDateTime
) {
    val id: String = _id
    val title: String = _title
    val ts: LocalDateTime = _time


    constructor(map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["title"].toString(),
                (ZonedDateTime.parse(map["ts"].toString())).toLocalDateTime()
            )


    @Override
    override fun toString(): String {
        val formatter: java.time.format.DateTimeFormatter =
            java.time.format.DateTimeFormatter.ofPattern("dd/MM - HH:mm");
        return ts.format(formatter) + " - " + title;
    }
}

internal class Asset(
    _id: String,
    _cod: String,
    _arAnchorID: String?,
    _function: BFunction?,
    _funcCategory: Category?,
    _tickets: ArrayList<SynTicket>,
    _events: ArrayList<SynEvent>
) {
    val id: String = _id
    val cod: String = _cod
    var anchorId: String? = _arAnchorID
    var function: BFunction? = _function
    var category: Category? = _funcCategory
    var tickets = _tickets
    var events = _events
    //"In Kotlin, the default implementation of MutableList is ArrayList
    // which you can think of as a resizable array."
    //List must have initialization size


    constructor(map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["cod"].toString(),
                if (map["ar_anchor"] != null) map["ar_anchor"].toString() else null,
                if (map["function"] != null)
                    BFunction(map["function"] as Map<String, Any>)
                else null,
                if (map["function"] != null && map["function_cat"] != null)
                    Category(map["function_cat"] as Map<String, Any>)
                else null,
                if (map["tickets"] != null) {
                    var jsonList = map["tickets"] as ArrayList<Map<String, Any>>
                    var tickets = jsonList.map { json -> SynTicket(json)}
                    ArrayList(tickets)
                } else {
                    ArrayList(0)
                },
                if (map["events"] != null) {
                    var jsonList = map["events"] as ArrayList<Map<String, Any>>
                    var events = jsonList.map { json -> SynEvent(json)}
                    ArrayList(events)
                } else {
                    ArrayList(0)
                }
            ) {
    }

    @Override
    override fun toString(): String {
        return if (anchorId != null) {
            "$cod (Already placed)"
        } else cod
    }
}