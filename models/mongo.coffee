sys: require 'sys'
url: require 'url'
require '../public/javascripts/underscore'
MongoDB: require('../lib/node-mongodb-native/lib/mongodb/db').Db
MongoServer: require('../lib/node-mongodb-native/lib/mongodb/connection').Server

class Mongo
  localUrl: 'http://localhost:27017/nodeko'
  constructor: ->
    @parseUrl process.env['MONGOHQ_URL'] or @localUrl
    @server: new MongoServer @host, @port
    @db: new MongoDB @dbname, @server
    if @user?
      @db.authenticate @user, @password, =>
        @db.open -> # no callback
    else @db.open -> # no callback

  parseUrl: (urlString)->
    uri: url.parse urlString
    @host: uri.hostname
    @port: parseInt(uri.port)
    @dbname: uri.pathname.replace(/^\//,'')
    [@user, @password]: uri.auth.split(':') if uri.auth?
exports.Mongo: Mongo

_.extend Mongo, {
  db: (new Mongo()).db

  bless: (klass) ->
    Serializer.bless klass
    _.extend klass.prototype, Mongo.InstanceMethods
    _.extend klass, Mongo.ClassMethods
    klass

  blessAll: (namespace) ->
    for name, klass of namespace
      klass::serialize: or name
      @bless klass

  InstanceMethods: {
    collection: (fn) ->
      Mongo.db.collection @serializer.name, fn

    save: (fn) ->
      @collection (error, collection) =>
        return fn error if error?
        serialized: Serializer.pack this
        collection.insert serialized, fn
  }

  ClassMethods: {
    all: (fn) ->
      @prototype.collection (error, collection) ->
        return fn error if error?
        collection.find (error, cursor) ->
          return fn error if error?
          cursor.toArray (error, array) ->
            return fn error if error?
            fn null, Serializer.unpack array
  }
}

class Serializer
  constructor: (klass, name, options) ->
    [@klass, @name]: [klass, name]

    @allowNesting: options?.allowNesting
    @allowed: {}
    for i in _.compact _.flatten [options?.exclude]
      @allowed[i]: false

    # constructorless copy of the class
    @copy: -> # empty constructor
    @copy.prototype: @klass.prototype # same prototype

  shouldSerialize: (name, value) ->
    return false unless value?
    @allowed[name] ?= _.isString(value) or
      _.isNumber(value) or
      _.isBoolean(value) or
      _.isArray(value) or
      value.serializer?.allowNesting

  pack: (instance) ->
    packed: { serializer: @name }
    for k, v of instance when @shouldSerialize(k, v)
      packed[k]: Serializer.pack v
    packed

  unpack: (data) ->
    unpacked: new @copy()
    for k, v of data when k isnt 'serializer'
      unpacked[k]: Serializer.unpack v
    unpacked

_.extend Serializer, {
  instances: {}

  pack: (data) ->
    if s: data?.serializer
      s.pack data
    else if _.isArray(data)
      Serializer.pack i for i in data
    else
      data

  unpack: (data) ->
    if s: Serializer.instances[data?.serializer]
      s.unpack data
    else if _.isArray(data)
      Serializer.unpack i for i in data
    else
      data

  bless: (klass) ->
    [name, options]: _.flatten [ klass::serialize ]
    klass::serializer: new Serializer(klass, name, options)
    Serializer.instances[name]: klass::serializer

  blessAll: (namespace) ->
    for k, v of namespace when v::serialize?
      Serializer.bless v
}