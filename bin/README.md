# diversity-ruby server script

## What do I need to run the diversity-ruby server?

- Any ruby interpreter compatible with MRI 2.0 (or later). The server
has been tested with MRI 2.1.3 and JRuby 1.7.16 (with the --2.0 flag set).

- Some rubygems
    - [sinatra](https://rubygems.org/gems/sinatra)
      The server has been tested with version 1.4.5 of sinatra.
    - [unirest](https://rubygems.org/gems/unirest)
      The server has been tested with version 1.1.2 of unirest.

- A backend supporting JSONRPC2 requests. Since the diversity-ruby server
is mostly used exclusively with Textalk's diversity framework at the moment,
some request methods are hardcoded, but as long as your backend responds
to these methods
([Url.get](http://api.textalk.se/webshop/files/Url-txt.html#Url.get),
[Theme.get](http://api.textalk.se/webshop/files/Theme-txt.html#Theme.get))
you should be able to run the server on any platform. In the future, you should
be able to specify what methods to call by specifying them in the configuration file.

## Configuring the server

Most of the servers actions are controlled by a single configuration file,
written in JSON. The server ships with a
[sample configuration file](../examples/config.sample.json) that you can use
as base when configuring the server.

### Fields in the configuration file

**backend** - The **backend** field tells the server where to ask for settings on how
to render diversity components. The **backend** field should be an JSON _object_ which
at least specifies  an **url** field. The **url** field should be a string representing
an absolute URL.

**environment** - The **environment** field describes how the server should treat
incoming URLs. The **environment** field is only needed if you intend to ask the backend
about _another_ URL than the URL the server is receiving. The server supports URL rewriting
when you specify an **host** field in the **enviroment**. The **host** should be a
JSON _object_ with a **type** field having either the value of "regexp" or "string". If it
is set to "regexp", the **pattern** field specifies a regexp that is used when doing the
url URL rewriting. If it is set to "string", the **name** field specifies which host name
to use instead of the one sent to the server.

**main_component** - The **main_component** field is used as a fallback when the backend
is unable to provide a a component class for the rendering. Normally, the component class is
decided upon by calling Theme.get in the backend with the value from a cookie called "tid"
(for _Theme id_). This field is optional but is useful for testing.

**registry** - The **registry** field is used to configure the component registry which is
responsible for delivering components to the rendering engine. At the moment, the server
supports two kinds of registries, _Local_ and _DiversityApi_. The _Local_ registry is the
simplest, using only a single folder in the file system. The _DiversityApi_ registry is
more complex, but can be placed independently (even on another domain). You specify which
kind of registry use want to use by setting the **type** property of the **registry**
object. You can also set **options** for the **registry**. Different options are supported
for the different kind of registries.

**server** - The **server** field configures how Sinatra should work. Every property you add
to the **server** object is sent straight to sinatra. Supported options can be found
[here](http://rubydoc.info/gems/sinatra#Available_Settings), but please note that you can only
use settings that can be safely expressed in JSON (ie strings, numbers, arrays, plain objects)
for now.

**settings** - The **settings** field is mainly used when testing component settings.
Normally, the settings are fetched using a call to Theme.get on the backend, so this field
is optional.

## Running the server

Run the server from the shell with

`bin/server.rb -c <configuration_file>`

If the configuration file can be read and the settings are valid, sinatra will start and
your server will be ready to recieve requests. Please note that the server is very much
alpha software right now, it does not handle errors very well yet.
