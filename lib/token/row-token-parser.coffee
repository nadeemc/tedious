# s2.2.7.17

sprintf = require('sprintf').sprintf

NULL = (1 << 16) - 1
THREE_AND_A_THIRD = 3 + (1 / 3)

parser = (buffer, columnsMetaData) ->
  columns = []
  for columnMetaData in columnsMetaData
    #console.log sprintf('Token @ 0x%02X', buffer.position)

    isNull = false
    value = undefined
    dataLength = undefined

    type = columnMetaData.type

    # s2.2.4.2.1
    switch type.id & 0x30
      when 0x10 # xx01xxxx - s2.2.4.2.1.1
        # Zero length
        dataLength = 0
      when 0x20 # xx10xxxx - s2.2.4.2.1.3
        # Variable length
        switch type.dataLengthLength
          when 1
            dataLength = buffer.readUInt8()
          when 2
            dataLength = buffer.readUInt16LE()
          when 4
            dataLength = buffer.readUInt32LE()
          else
            throw Error("Unsupported dataLengthLength #{type.dataLengthLength} for data type #{type.name}")
      when 0x30 # xx11xxxx - s2.2.4.2.1.2
        # Fixed length
        dataLength = 1 << ((type.id & 0x0C) >> 2)

    switch type.name
      when 'Null'
        isNull = true
      when 'TinyInt'
        value = buffer.readUInt8()
      when 'Int'
        value = buffer.readInt32LE()
      when 'SmallInt'
        value = buffer.readInt16LE()
      when 'BigInt'
        value = buffer.readAsStringInt64LE()
      when 'IntN'
        switch dataLength
          when 0
            isNull = true
          when 1
            value = buffer.readInt8()
          when 2
            value = buffer.readInt16LE()
          when 4
            value = buffer.readInt32LE()
          when 8
            value = buffer.readAsStringInt64LE()
      when 'Bit'
        value = !!buffer.readUInt8()
      when 'BitN'
        switch dataLength
          when 0
            isNull = true
          when 1
            value = !!buffer.readUInt8()
      when 'VarChar', 'Char'
        {value: value, isNull: isNull} = readChars(buffer, dataLength, 'ascii')
      when 'NVarChar', 'NChar'
        {value: value, isNull: isNull} = readChars(buffer, dataLength, 'ucs2')
      when 'SmallDateTime'
        value = readSmallDateTime(buffer)
      when 'DateTime'
        value = readDateTime(buffer)
      when 'DateTimeN'
        switch dataLength
          when 0
            isNull = true
          when 4
            value = readSmallDateTime(buffer)
          when 8
            value = readDateTime(buffer)
      when 'NumericN', 'DecimalN'
        if dataLength == 0
          isNull = true
        else
          sign = if buffer.readUInt8() == 1 then 1 else -1

          switch dataLength - 1
            when 4
              value = buffer.readUInt32LE()
            when 8
              value = buffer.readUNumeric64LE()
            when 12
              value = buffer.readUNumeric96LE()
            when 16
              value = buffer.readUNumeric128LE()
            else
              error = sprintf('Unsupported numeric size %d at offset 0x%04X', dataLength - 1, buffer.position)
              break

          value *= sign
          value /= Math.pow(10, columnMetaData.scale)
      else
        error = sprintf('Unrecognised column type %s at offset 0x%04X', type.name, (buffer.position - 1))
        break

    columns.push(
      value: value
      isNull: isNull,
      metadata: columnMetaData
    )

  columns.byName = ->
    byName = {}

    for column in columns
      byName[column.metadata.colName] = column

    byName

  if error
    token =
      name: 'ROW'
      error: error
  else
    token =
      name: 'ROW'
      event: 'row'
      columns: columns

readChars = (buffer, dataLength, encoding) ->
  if dataLength == NULL
    value: undefined
    isNull: true
  else
    value: buffer.readString(dataLength, encoding)
    isNull: false

readSmallDateTime = (buffer) ->
  days = buffer.readUInt16LE()
  minutes = buffer.readUInt16LE()

  value = new Date(1900, 0, 1)
  value.setDate(value.getDate() + days)
  value.setMinutes(value.getMinutes() + minutes)
  value

readDateTime = (buffer) ->
  days = buffer.readInt32LE()
  threeHundredthsOfSecond = buffer.readUInt32LE()
  milliseconds = threeHundredthsOfSecond * THREE_AND_A_THIRD

  value = new Date(1900, 0, 1)
  value.setDate(value.getDate() + days)
  value.setMilliseconds(value.getMilliseconds() + milliseconds)
  value

module.exports = parser