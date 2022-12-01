package io.carius.lars.ar_flutter_plugin
import android.os.Build
import androidx.annotation.RequiresApi


class Asset(_id: String, _cod: String, _arAnchorID: String = "") {
    val id: String  = _id
    val cod: String = _cod
    var arAnchorID: String = _arAnchorID

    constructor(json: Map<String, Any>):this(json["id"].toString(), json["cod"].toString(), json["ar_anchor"].toString()) {}

}

//some fields have default values to mimic behavior in Asset.java

internal class BaseFunctionCategory (_id: String = "", _cod: String = "", _name: String = "", _color: String = "") {
    val ID: String  = _id
    val Color: String = _color
    val Name: String = _name
    val Cod: String = _cod
    //TODO check alternative for toString()
    constructor (map: Map<String, Any>) : 
        this (
            map["id"].toString(),
            (if (map.containsKey("color")) map["color"].toString() else ""),
            map["name"].toString(),
            map["cod"].toString()
        ) {}
}

@RequiresApi(Build.VERSION_CODES.O) //required for java.time format
internal class SynTicket (_id: String = "",
                          _title: String = "",
                          _time: java.time.LocalDateTime =
                              java.time.LocalDateTime.of(0, 1, 1, 1, 0)
                         ) {
    val ID: String  = _id
    val Title: String = _title
    val Time: java.time.LocalDateTime = _time


    constructor(map: Map<String, Any>) :
            this (
                map["id"].toString(),
                map["title"].toString(),
                (java.time.ZonedDateTime.parse(map["ts"].toString())).toLocalDateTime()
            ) {}


    @Override
    override fun toString(): String {
        val formatter : java.time.format.DateTimeFormatter = java.time.format.DateTimeFormatter.ofPattern("dd/MM - HH:mm");
        return Time.format(formatter)+" - "+Title;
    }
}


@RequiresApi(Build.VERSION_CODES.O) //required for java.time format
internal class SynEvent (_id: String = "",
                         _title: String = "",
                         _time: java.time.LocalDateTime =
                             java.time.LocalDateTime.of(0, 1, 1, 1, 0)
                        ) {
    val ID: String = _id
    val Title: String = _title
    val Time: java.time.LocalDateTime = _time


    constructor(map: Map<String, Any>) :
            this(
                map["id"].toString(),
                map["title"].toString(),
                (java.time.ZonedDateTime.parse(map["ts"].toString())).toLocalDateTime()
            )


    @Override
    override fun toString(): String {
        val formatter : java.time.format.DateTimeFormatter = java.time.format.DateTimeFormatter.ofPattern("dd/MM - HH:mm");
        return Time.format(formatter)+" - "+Title;
    }
}

internal class RealAsset(_id: String,
                     _cod: String,
                     _arAnchorID: String,
                     _function: BaseFunctionCategory = BaseFunctionCategory(),
                     _funcCategory: BaseFunctionCategory = BaseFunctionCategory(),
                     _tickets: MutableList<SynTicket> = mutableListOf(),
                     _events: MutableList<SynEvent> = mutableListOf()
                     ) {
    val ID: String  = _id
    val Cod: String = _cod
    var ARanchorID: String = _arAnchorID
    var Function: BaseFunctionCategory = _function
    var FuncCategory: BaseFunctionCategory = _funcCategory
    var Tickets = _tickets
    var Events = _events
    //"In Kotlin, the default implementation of MutableList is ArrayList
    // which you can think of as a resizable array."
    //List must have initialization size


    constructor(map: Map<String, Any>) :
        this(
            map["id"].toString(), 
            map["cod"].toString(),
            if (map.containsKey("ar_anchor")) map["ar_anchor"].toString() else "",
            if(map.containsKey("function"))
                BaseFunctionCategory(map["function"] as Map<String, Any>)
            else BaseFunctionCategory(),
            if(map.containsKey("function") && map.containsKey("function_cat"))
                BaseFunctionCategory(map["function_cat"] as Map<String, Any>)
            else BaseFunctionCategory(),
            if(map.containsKey("tickets")) (map["tickets"] as MutableList<SynTicket>) else mutableListOf<SynTicket>(),
            if(map.containsKey("events")) (map["events"] as MutableList<SynEvent>) else mutableListOf<SynEvent>()
        ) {}

    fun fromMapToListToMapAgain (map: Map<String, Any>) {
        //can be deleted after testing
        //depending on what Assets.java.Assets -> Tickets = tt; actually does
        var listOfTickets : List<SynTicket> = (map["tickets"] as MutableList<SynTicket>).toList();
        //listOfTickets should be == [ticket1, ticket2, ticket3, ... , ticket n-1]
        // list -> map{"$i : $listOfTickets[i]"}
        val mapOfTickets = listOfTickets.mapIndexed { index: Int, s: SynTicket -> index + 1 to s }.toMap()
    }
}

    private fun createFromMap(map: Map<String, Any>) {

    }
    



    @Override
    override fun toString(): String {
        return if (ARanchorID.isNotEmpty()) {
            "$Cod (Already placed)"
        } else Cod!!
    }

}