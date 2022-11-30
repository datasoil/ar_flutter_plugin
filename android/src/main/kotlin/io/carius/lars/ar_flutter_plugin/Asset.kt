package io.carius.lars.ar_flutter_plugin

internal class Asset(_id: String, _cod: String, _arAnchorID: String = "") {
    val id: String  = _id
    val cod: String = _cod
    var arAnchorID: String = _arAnchorID

    constructor(json: Map<String, Any>):this(json["id"].toString(), json["cod"].toString(), json["ar_anchor"].toString()) {}

    @Override
    override fun toString(): String {
        return if (arAnchorID.isNotEmpty()) {
            "$cod (Already placed)"
        } else cod!!
    }

}