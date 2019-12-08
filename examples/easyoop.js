(function(){

'use strict';

(function() {
    /**
     * WEB environment implementation. Provides elementary API zebkit needs to perform an
     * environment specific operations.
     * @class environment
     * @access package
     */
    var zebkitEnvironment = function() {
        var pkg    = {},
            hostRe = /([a-zA-Z]+)\:\/\/([^/:]+)/,
            isFF   = typeof navigator !== 'undefined' &&
                     navigator.userAgent.toLowerCase().indexOf('firefox') >= 0;

        function $sleep() {
            var r = new XMLHttpRequest(),
                t = (new Date()).getTime().toString(),
                i = window.location.toString().lastIndexOf("?");
            r.open('GET', window.location + (i > 0 ? "&" : "?") + t, false);
            r.send(null);
        }

        function $Request() {
            this.responseText = this.statusText = "";
            this.onreadystatechange = this.responseXml = null;
            this.readyState = this.status = 0;
        }

        $Request.prototype.open = function(method, url, async, user, password) {
            var m = url.match(hostRe);
            if (window.location.scheme.toLowerCase() === "file:" ||
                  (m    !== null &&
                   m[2] !== undefined &&
                   m[2].toLowerCase() === window.location.host.toLowerCase()))
            {
                this._request = new XMLHttpRequest();
                this._xdomain = false;

                var $this = this;
                this._request.onreadystatechange = function() {
                    $this.readyState = $this._request.readyState;
                    if ($this._request.readyState === 4) {
                        $this.responseText = $this._request.responseText;
                        $this.responseXml  = $this._request.responseXml;
                        $this.status       = $this._request.status;
                        $this.statusText   = $this._request.statusText;
                    }

                    if ($this.onreadystatechange) {
                        $this.onreadystatechange();
                    }
                };

                return this._request.open(method, url, (async !== false), user, password);
            } else {
                this._xdomain = true;
                this._async = (async === true);
                this._request = new XDomainRequest();
                return this._request.open(method, url);
            }
        };

        $Request.prototype.send = function(data) {
            if (this._xdomain) {
                var originalReq = this._request,
                    $this       = this;

                //!!!! handler has to be defined after
                //!!!! open method has been called and all
                //!!!! four handlers have to be defined
                originalReq.ontimeout = originalReq.onprogress = function () {};

                originalReq.onerror = function() {
                    $this.readyState = 4;
                    $this.status = 404;
                    if ($this._async && $this.onreadystatechange) {
                        $this.onreadystatechange();
                    }
                };

                originalReq.onload  = function() {
                    $this.readyState = 4;
                    $this.status = 200;

                    if ($this._async && $this.onreadystatechange) {
                        $this.onreadystatechange(originalReq.responseText, originalReq);
                    }
                };

                //!!! set time out zero to prevent data lost
                originalReq.timeout = 0;

                if (this._async === false) {
                    originalReq.send(data);

                    while (this.status === 0) {
                        $sleep();
                    }

                    this.readyState = 4;
                    this.responseText = originalReq.responseText;

                } else {
                    //!!!  short timeout to make sure bloody IE is ready
                    setTimeout(function () {
                       originalReq.send(data);
                    }, 10);
                }
            } else  {
                return this._request.send(data);
            }
        };

        $Request.prototype.abort = function(data) {
            return this._request.abort();
        };

        $Request.prototype.setRequestHeader = function(name, value) {
            if (this._xdomain) {
                if (name === "Content-Type") {
                    //!!!
                    // IE8 and IE9 anyway don't take in account the assignment
                    // IE8 throws exception every time a value is assigned to
                    // the property
                    // !!!
                    //this._request.contentType = value;
                    return;
                } else {
                    throw new Error("Method 'setRequestHeader' is not supported for " + name);
                }
            } else {
                this._request.setRequestHeader(name, value);
            }
        };

        $Request.prototype.getResponseHeader = function(name) {
            if (this._xdomain) {
                throw new Error("Method is not supported");
            }
            return this._request.getResponseHeader(name);
        };

        $Request.prototype.getAllResponseHeaders = function() {
            if (this._xdomain) {
                throw new Error("Method is not supported");
            }
            return this._request.getAllResponseHeaders();
        };

        /**
         * Build HTTP request that provides number of standard methods, fields and listeners:
         *
         *    - "open(method, url [,async])" - opens the given URL
         *    - "send(data)"   - sends data
         *    - "status"       - HTTP status code
         *    - "statusText"   - HTTP status text
         *    - "responseText" - response text
         *    - "readyState"   - request ready state
         *    - "onreadystatechange()" - ready state listener
         *
         * @return {Object} an HTTP request object
         * @method getHttpRequest
         */
        pkg.getHttpRequest = function() {
            var r = new XMLHttpRequest();
            if (isFF) {
                r.__send = r.send;
                r.send = function(data) {
                    // !!! FF can throw NS_ERROR_FAILURE exception instead of
                    // !!! returning 404 File Not Found HTTP error code
                    // !!! No request status, statusText are defined in this case
                    try {
                        return this.__send(data);
                    } catch(e) {
                        if (!e.message || e.message.toUpperCase().indexOf("NS_ERROR_FAILURE") < 0) {
                            // exception has to be re-instantiate to be Error class instance
                            throw new Error(e.toString());
                        }
                    }
                };
            }
            return ("withCredentials" in r) ? r  // CORS is supported out of box
                                            : new $Request(); // IE
        };

        pkg.parseXML = function(s) {
            function rmws(node) {
                if (node.childNodes !== null) {
                    for (var i = node.childNodes.length; i-- > 0;) {
                        var child= node.childNodes[i];
                        if (child.nodeType === 3 && child.data.match(/^\s*$/) !== null) {
                            node.removeChild(child);
                        }

                        if (child.nodeType === 1) {
                            rmws(child);
                        }
                    }
                }
                return node;
            }

            if (typeof DOMParser !== "undefined") {
                return rmws((new DOMParser()).parseFromString(s, "text/xml"));
            } else {
                for (var n in { "Microsoft.XMLDOM":0, "MSXML2.DOMDocument":1, "MSXML.DOMDocument":2 }) {
                    var p = null;
                    try {
                        p = new ActiveXObject(n);
                        p.async = false;
                    } catch (e) {
                        continue;
                    }

                    if (p === null) {
                        throw new Error("XML parser is not available");
                    }
                    p.loadXML(s);
                    return p;
                }
            }
            throw new Error("No XML parser is available");
        };

        /**
         * Loads an image by the given URL.
         * @param  {String|HTMLImageElement} img an image URL or image object
         * @param  {Function} success a call back method to be notified when the image has
         * been successfully loaded. The method gets an image as its parameter.
         * @param {Function} [error] a call back method to be notified if the image loading
         * has failed. The method gets an image instance as its parameter and an exception
         * that describes an error has happened.
         *
         * @example
         *      // load image
         *      zebkit.environment.loadImage("test.png", function(image) {
         *           // handle loaded image
         *           ...
         *      }, function (img, exception) {
         *          // handle error
         *          ...
         *      });
         *
         * @return {HTMLImageElement}  an image
         * @method loadImage
         */
        pkg.loadImage = function(ph, success, error) {
            var img = null;
            if (ph instanceof Image) {
                img = ph;
            } else {
                img = new Image();
                img.crossOrigin = '';
                img.crossOrigin ='anonymous';
                img.src = ph;
            }

            if (img.complete === true && img.naturalWidth !== 0) {
                success.call(this, img);
            } else {
                var pErr  = img.onerror,
                    pLoad = img.onload,
                    $this = this;

                img.onerror = function(e) {
                    img.onerror = null;
                    try {
                        if (error !== undefined) {
                            error.call($this, img, new Error("Image '" + ph + "' cannot be loaded " + e));
                        }
                    } finally {
                        if (typeof pErr === 'function') {
                            img.onerror = pErr;
                            pErr.call(this, e);
                        }
                    }
                };

                img.onload  = function(e) {
                    img.onload = null;
                    try {
                        success.call($this, img);
                    } finally {
                        if (typeof pLoad === 'function') {
                            img.onload = pLoad;
                            pLoad.call(this, e);
                        }
                    }
                };
            }

            return img;
        };

        /**
         * Parse JSON string
         * @param {String} json a JSON string
         * @method parseJSON
         * @return {Object} parsed JSON as an JS Object
         */
        pkg.parseJSON = JSON.parse;

        /**
         * Convert the given JS object into an JSON string
         * @param {Object} jsonObj an JSON JS object to be converted into JSON string
         * @return {String} a JSON string
         * @method stringifyJSON
         *
         */
        pkg.stringifyJSON = JSON.stringify;

        /**
         * Call the given callback function repeatedly with the given calling interval.
         * @param {Function} cb a callback function to be called
         * @param {Integer}  time an interval in milliseconds the given callback
         * has to be called
         * @return {Integer} an run interval id
         * @method setInterval
         */
        pkg.setInterval = function (cb, time) {
            return window.setInterval(cb, time);
        };

        /**
         * Clear the earlier started interval calling
         * @param  {Integer} id an interval id
         * @method clearInterval
         */
        pkg.clearInterval = function (id) {
            return window.clearInterval(id);
        };

        if (typeof window !== 'undefined') {
            var $taskMethod = window.requestAnimationFrame       ||
                              window.webkitRequestAnimationFrame ||
                              window.mozRequestAnimationFrame    ||
                              function(callback) { return setTimeout(callback, 35); };


            pkg.decodeURIComponent = window.decodeURIComponent;
            pkg.encodeURIComponent = window.encodeURIComponent;

        } else {
            pkg.decodeURIComponent = function(s) { return s; } ;
            pkg.encodeURIComponent = function(s) { return s; } ;
        }

        /**
         * Request to run a method as an animation task.
         * @param  {Function} f the task body method
         * @method  animate
         */
        pkg.animate = function(f){
            return $taskMethod.call(window, f);
        };

        function buildFontHelpers() {
            //  font metrics API
            var e = document.getElementById("zebkit.fm");
            if (e === null) {
                e = document.createElement("div");
                e.setAttribute("id", "zebkit.fm");  // !!! position fixed below allows to avoid 1px size in HTML layout for "zebkit.fm" element
                e.setAttribute("style", "visibility:hidden;line-height:0;height:1px;vertical-align:baseline;position:fixed;");
                e.innerHTML = "<span id='zebkit.fm.text' style='display:inline;vertical-align:baseline;'>&nbsp;</span>";
                document.body.appendChild(e);
            }
            var $fmCanvas = document.createElement("canvas").getContext("2d"),
                $fmText   = document.getElementById("zebkit.fm.text");

            pkg.fontMeasure = $fmCanvas;

            pkg.fontStringWidth = function(font, str) {
                if (str.length === 0) {
                    return 0;
                } else {
                    if ($fmCanvas.font !== font) {
                        $fmCanvas.font = font;
                    }
                    return Math.round($fmCanvas.measureText(str).width);
                }
            };

            pkg.fontMetrics = function(font) {
                if ($fmText.style.font !== font) {
                    $fmText.style.font = font;
                }
                return { height : $fmText.offsetHeight };
            };
        }

        if (typeof document !== 'undefined') {
            document.addEventListener("DOMContentLoaded", buildFontHelpers);
        }

        return pkg;
    };

    if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
        module.exports.zebkitEnvironment = zebkitEnvironment;

        // TODO:
        // typeof the only way to make environment visible is makling it global
        // since module cannot be applied in the ase of browser context
        if (typeof global !== 'undefined') {
            global.zebkitEnvironment = zebkitEnvironment;
        }
    } else {
        window.zebkitEnvironment = zebkitEnvironment;
    }
})();
/**
 * Promise-like sequential tasks runner (D-then). Allows developers to execute
 * number of steps (async and sync) in the exact order they have been called with
 * the class instance. The idea of the runner implementation is making the
 * code more readable and plain nevertheless it includes asynchronous parts:
 * @example
 *
 *     var r = new zebkit.DoIt();
 *
 *     // step 1
 *     r.then(function() {
 *         // call three asynchronous HTTP GET requests to read three files
 *         // pass join to every async. method to be notified when the async.
 *         // part is completed
 *         asyncHttpCall("http://test.com/a.txt", this.join());
 *         asyncHttpCall("http://test.com/b.txt", this.join());
 *         asyncHttpCall("http://test.com/c.txt", this.join());
 *     })
 *     .  // step 2
 *     then(function(r1, r2, r3) {
 *         // handle completely read on previous step files
 *         r1.responseText  // "a.txt" file content
 *         r2.responseText  // "b.txt" file content
 *         r3.responseText  // "c.txt" file content
 *     })
 *     . // handle error
 *     catch(function(e) {
 *         // called when an exception has occurred
 *         ...
 *     });
 *
 *
 * @class zebkit.DoIt
 * @param {Boolean} [ignore] flag to rule error ignorance
 * @constructor
 */
function DoIt(body, ignore) {
    this.recover();

    if (arguments.length === 1) {
        if (body !== undefined && body !== null && (typeof body === "boolean" || body.constructor === Boolean)) {
            this.$ignoreError = body;
            body = null;
        } else {
            this.then(body);
        }
    } else if (arguments.length === 2) {
        this.$ignoreError = ignore;
        this.then(body);
    }
}

DoIt.prototype = {
    /**
     * Indicates if the error has to be ignored
     * @attribute $ignoreError
     * @private
     * @type {Boolean}
     */
    $ignoreError : false,

    // TODO: not stable API
    recover : function(body) {
        if (this.$error !== null) {
            var err = this.$error;
            this.$error = null;
            this.$tasks   = [];
            this.$results = [];
            this.$taskCounter = this.$level = this.$busy = 0;

            if (arguments.length === 1) {
                body.call(this, err);
            }
        }
        return this;
    },

    /**
     * Restart the do it object to clear error that has happened and
     * continue tasks that has not been run yet because of the error.
     * @method  restart
     * @chainable
     */
    restart : function() {
        if (this.$error !== null) {
            this.$error = null;
        }
        this.$schedule();
        return this;
    },

    /**
     * Run the given method as one of the sequential step of the doit execution.
     * @method  then
     * @param  {Function} body a method to be executed. The method can get results
     * of previous step execution as its arguments. The method is called in context
     * of a DoIt instance.
     * @chainable
     */
    then : function(body, completed) {
        var level = this.$level;  // store level then was executed for the given task
                                  // to be used to compute correct the level inside the
                                  // method below
        if (body instanceof DoIt) {
            if (body.$error !== null) {
                this.error(body.$error);
            } else {
                var $this = this;
                this.then(function() {
                    var jn = $this.join();
                    body.then(function() {
                        if (arguments.length > 0) {
                            // also pass result to body DoIt
                            this.join.apply(this, arguments);
                        }
                    }, function() {
                        if ($this.$error === null) {
                            jn.apply($this, arguments);
                        }
                    }).catch(function(e) {
                        $this.error(e);
                    });
                });
            }

            return this;
        } else {
            var task = function() {
                // clean results of execution of a previous task

                this.$busy = 0;
                var pc = this.$taskCounter, args = null, r;

                if (this.$error === null) {
                    if (this.$results[level] !== undefined) {
                        args = this.$results[level];
                    }

                    this.$taskCounter    = 0;  // we have to count the tasks on this level
                    this.$level          = level + 1;
                    this.$results[level] = [];

                    // it is supposed the call is embedded with other call, no need to
                    // catch it one more time
                    if (level > 0) {
                        r = body.apply(this, args);
                    } else {
                        try {
                            r = body.apply(this, args);
                        } catch(e) {
                            this.error(e);
                        }
                    }

                    // this.$busy === 0 means we have called synchronous task
                    // and make sure the task has returned a result
                    if (this.$busy === 0 && this.$error === null && r !== undefined) {
                        this.$results[level] = [ r ];
                    }
                }

                if (level === 0) {
                    // zero level is responsible for handling exception
                    try {
                        this.$schedule();
                    } catch(e) {
                        this.error(e);
                    }
                } else {
                    this.$schedule();
                }

                this.$level = level; // restore level
                this.$taskCounter = pc;  // restore counter

                // TODO: not a graceful solution. It has been done to let call "join" out
                // outside of body. Sometimes it is required to provide proper level of
                // execution since join calls schedule
                if (typeof completed === 'function') {
                    if (level === 0) {
                        try {
                            if (args === null) {
                                completed.call(this);
                            } else {
                                completed.apply(this, args);
                            }
                        } catch(e) {
                            this.error(e);
                        }
                    } else {
                        if (args === null) {
                            completed.call(this);
                        } else {
                            completed.apply(this, args);
                        }
                    }
                }
                if (args !== null) {
                    args.length = 0;
                }
            };

            if (this.$error === null) {
                if (level === 0 && this.$busy === 0) {
                    if (this.$results[level] !== null &&
                        this.$results[level] !== undefined &&
                        this.$results[level].length > 0)
                    {
                        task.apply(this, this.$results[level]);
                    } else {
                        task.call(this);
                    }
                } else {
                    // put task in list
                    if (this.$level > 0) {
                        this.$tasks.splice(this.$taskCounter++, 0, task);
                    } else {
                        this.$tasks.push(task);
                    }
                }
            }
        }

        if (this.$level === 0) {
            this.$schedule();
        }

        return this;
    },

    $ignored : function(e) {
        this.dumpError(e);
    },

    /**
     * Force to fire error.
     * @param  {Error} [e] an error to be fired
     * @method error
     * @chainable
     */
    error : function(e, pr) {
        if (arguments.length === 0) {
            if (this.$error !== null) {
                this.dumpError(e);
            }
        } else {
            if (this.$error === null) {
                if (this.$ignoreError) {
                    this.$ignored(e);
                } else {
                    this.$taskCounter = this.$level = this.$busy = 0;
                    this.$error   = e;
                    this.$results = [];
                }

                this.$schedule();
            } else if (arguments.length < 2 || pr === true) {
                this.dumpError(e);
            }
        }

        return this;
    },

    /**
     * Wait for the given doit redness.
     * @param  {zebkit.DoIt} r a runner
     * @example
     *
     *      var async = new DoIt().then(function() {
     *          // imagine we do asynchronous ajax call
     *          ajaxCall("http://test.com/data", this.join());
     *      });
     *
     *      var doit = new DoIt().till(async).then(function(res) {
     *          // handle result that has been fetched
     *          // by "async" do it
     *          ...
     *      });
     *
     * @chainable
     * @method till
     */
    till : function(r) {
        // wait till the given DoIt is executed
        this.then(function() {
            var $this = this,
                jn    = this.join(), // block execution of the runner
                res   = arguments.length > 0 ? Array.prototype.slice.call(arguments) : []; // save arguments to restore it later

            // call "doit" we are waiting for
            r.then(function() {
                if ($this.$error === null) {
                    // unblock the doit that waits for the runner we are in and
                    // restore its arguments
                    if (res.length > 0) {
                        jn.apply($this, res);
                    } else {
                        jn.call($this);
                    }

                    // preserve arguments for the next call
                    if (arguments.length > 0) {
                        this.join.apply(this, arguments);
                    }
                }
            }).catch(function(e) {
                // delegate error to a waiting runner
                $this.error(e);
            });
        });

        return this;
    },

    /**
     * Returns join callback for asynchronous parts of the doit. The callback
     * has to be requested and called by an asynchronous method to inform the
     * doit the given method is completed.
     * @example
     *
     *      var d = new DoIt().then(function() {
     *          // imagine we call ajax HTTP requests
     *          ajaxCall("http://test.com/data1", this.join());
     *          ajaxCall("http://test.com/data2", this.join());
     *      }).then(function(res1, res2) {
     *          // handle results of ajax requests from previous step
     *          ...
     *      });
     *
     * @return {Function} a method to notify doit the given asynchronous part
     * has been completed. The passed to the method arguments will be passed
     * to the next step of the runner.         *
     * @method join
     */
    join : function() {
        // if join is called outside runner than level is set to 0
        var level = this.$level === 0 ? 0 : this.$level - 1;

        if (arguments.length > 0) {
            this.$results[level] = [];
            for(var i = 0; i < arguments.length; i++) {
                this.$results[level][i] = arguments[i];
            }
        } else {
            // TODO: join uses busy flag to identify the result index the given join will supply
            // what triggers a potential result overwriting  problem (jn2 overwrite jn1  result):
            //    var jn1 = join(); jn1();
            //    var jn2 = join(); jn2();

            var $this = this,
                index = this.$busy++;

            return function() {
                if ($this.$results[level] === null || $this.$results[level] === undefined) {
                    $this.$results[level] = [];
                }

                // since error can occur and times variable
                // can be reset to 0 we have to check it
                if ($this.$busy > 0) {
                    var i = 0;

                    if (arguments.length > 0) {
                        $this.$results[level][index] = [];
                        for(i = 0; i < arguments.length; i++) {
                            $this.$results[level][index][i] = arguments[i];
                        }
                    }

                    if (--$this.$busy === 0) {
                        // collect result
                        if ($this.$results[level].length > 0) {
                            var args = $this.$results[level],
                                res  = [];

                            for(i = 0; i < args.length; i++) {
                                Array.prototype.push.apply(res, args[i]);
                            }
                            $this.$results[level] = res;
                        }

                        // TODO: this code can bring to unexpected scheduling for a situation when
                        // doit is still in then:
                        //    then(function () {
                        //        var jn1 = join();
                        //        ...
                        //        jn1()  // unexpected scheduling of the next then since busy is zero
                        //        ...
                        //        var jn2 = join(); // not actual
                        //    })

                        $this.$schedule();
                    }
                }
            };
        }
    },

    /**
     * Method to catch error that has occurred during the doit sequence execution.
     * @param  {Function} [body] a callback to handle the error. The method
     * gets an error that has happened as its argument. If there is no argument
     * the error will be printed in output. If passed argument is null then
     * no error output is expected.
     * @chainable
     * @method catch
     */
    catch : function(body) {
        var level = this.$level;  // store level then was executed for the given task
                                  // to be used to compute correct the level inside the
                                  // method below

        var task = function() {
            // clean results of execution of a previous task

            this.$busy = 0;
            var pc = this.$taskCounter;
            if (this.$error !== null) {
                this.$taskCounter = 0;  // we have to count the tasks on this level
                this.$level       = level + 1;

                try {
                    if (typeof body === 'function') {
                        body.call(this, this.$error);
                    } else if (body === null) {

                    } else {
                        this.dumpError(this.$error);
                    }
                } catch(e) {
                    this.$level       = level; // restore level
                    this.$taskCounter = pc;    // restore counter
                    throw e;
                }
            }

            if (level === 0) {
                try {
                    this.$schedule();
                } catch(e) {
                    this.error(e);
                }
            } else {
                this.$schedule();
            }

            this.$level       = level; // restore level
            this.$taskCounter = pc;    // restore counter
        };

        if (this.$level > 0) {
            this.$tasks.splice(this.$taskCounter++, 0, task);
        } else {
            this.$tasks.push(task);
        }

        if (this.$level === 0) {
            this.$schedule();
        }

        return this;
    },

    /**
     * Throw an exception if an error has happened before the method call,
     * otherwise do nothing.
     * @method  throw
     * @chainable
     */
    throw : function() {
        return this.catch(function(e) {
            throw e;
        });
    },

    $schedule : function() {
        if (this.$tasks.length > 0 && this.$busy === 0) {
            this.$tasks.shift().call(this);
        }
    },

    end : function() {
        this.recover();
    },

    dumpError: function(e) {
        if (typeof console !== "undefined" && console.log !== undefined) {
            if (e === null || e === undefined) {
                console.log("Unknown error");
            } else {
                console.log((e.stack ? e.stack : e));
            }
        }
    }
};

// Environment specific stuff
var $exports     = {},
    $zenv        = {},
    $global      = (typeof window !== "undefined" && window !== null) ? window
                                                                     : (typeof global !== 'undefined' ? global
                                                                                                      : this),
    $isInBrowser = typeof navigator !== "undefined",
    isIE         = $isInBrowser && (Object.hasOwnProperty.call(window, "ActiveXObject") ||
                                  !!window.ActiveXObject ||
                                  window.navigator.userAgent.indexOf("Edge") > -1),
    isFF         = $isInBrowser && window.mozInnerScreenX !== null && window.navigator.userAgent && window.navigator.userAgent.toLowerCase().indexOf("firefox") > 0,
    isMacOS      = $isInBrowser && navigator.platform.toUpperCase().indexOf('MAC') !== -1,
    $FN          = null;

/**
 * Reference to global space.
 * @attribute $global
 * @private
 * @readOnly
 * @type {Object}
 * @for zebkit
 */

if (parseInt.name !== "parseInt") {
    $FN = function(f) {  // IE stuff
        if (f.$methodName === undefined) { // test if name has been earlier detected
            var mt = f.toString().match(/^function\s+([^\s(]+)/);
                f.$methodName = (mt === null) ? ''
                                              : (mt[1] === undefined ? ''
                                                                     : mt[1]);
        }
        return f.$methodName;
    };
} else {
    $FN = function(f) {
        return f.name;
    };
}

function $export() {
    for (var i = 0; i < arguments.length; i++) {
        var arg = arguments[i];
        if (typeof arg === 'function') {
            $exports[$FN(arg)] = arg;
        } else {
            for (var k in arg) {
                if (arg.hasOwnProperty(k)) {
                    $exports[k] = arg[k];
                }
            }
        }
    }
}

if (typeof zebkitEnvironment === 'function') {
    $zenv = zebkitEnvironment();
} else if (typeof window !== 'undefined') {
    $zenv = window;
}

function $buildReqError(url, req) {
    var e = new Error("HTTP error '" + req.statusText + "', code = " + req.status + " '" + url + "'");
    e.status     = req.status;
    e.statusText = req.statusText;
    e.readyState = req.readyState;
    return e;
}

function GET(url) {
    var req = $zenv.getHttpRequest();
    req.open("GET", url, true);

    return new DoIt(function() {
        var jn    = this.join(),
            $this = this;

        req.onreadystatechange = function() {
            if (req.readyState === 4) {
                // evaluate HTTP response
                if (req.status >= 400 || req.status < 100) {
                    $this.error($buildErrorByResponse(url, req));
                } else {
                    jn(req);
                }
            }
        };

        try {
            req.send(null);
        } catch(e) {
            this.error(e);
        }
    });
}

function HEAD(url) {
    var req = $zenv.getHttpRequest();
    req.open("HEAD", url, true);

    return new DoIt(function() {
        var jn    = this.join(),
            $this = this;

        req.onreadystatechange = function() {
            if (req.readyState === 4) {
                // evaluate HTTP response
                if (req.status == 404) {
                    jn(false);
                } else  if (req.status >= 400 || req.status < 100) {
                    $this.error($buildErrorByResponse(url, req));
                } else {
                    jn(true);
                }
            }
        };

        try {
            req.send(null);
        } catch(e) {
            this.error(e);
        }
    });
}


// Micro file system
var ZFS = {
    catalogs : {},

    load: function(pkg, files) {
        var catalog = this.catalogs[pkg];
        if (catalog === undefined) {
            catalog = {};
            this.catalogs[pkg] = catalog;
        }

        for(var file in files) {
            catalog[file] = files[file];
        }
    },

    read : function(uri) {
        var p = null;
        for(var catalog in this.catalogs) {
            var pkg   = zebkit.byName(catalog),
                files = this.catalogs[catalog];

            if (pkg === null) {
                throw new ReferenceError("'" + catalog + "'");
            }

            p = new URI(uri).relative(pkg.$url);
            if (p !== null && files[p] !== undefined && files[p] !== null) {
                return files[p];
            }
        }
        return null;
    },

    touch : function(uri) {
        var f = ZFS.read(uri);
        if (f !== null) {
            return new DoIt(function() {
                return true;
            });
        } else {
            return HEAD(uri);
        }
    },

    GET: function(uri) {
        var f = ZFS.read(uri);
        if (f !== null) {
            return new DoIt(function() {
                return {
                    status      : 200,
                    statusText  : "",
                    extension   : f.ext,
                    responseText: f.data
                };
            });
        } else {
            return GET(uri);
        }
    }
};

/**
 * Dump the given error to output.
 * @param  {Exception | Object} e an error.
 * @method dumpError
 * @for  zebkit
 */
function dumpError(e) {
    if (typeof console !== "undefined" && typeof console.log !== "undefined") {
        var msg = "zebkit.err [";
        if (typeof Date !== 'undefined') {
            var date = new Date();
            msg = msg + date.getDate()   + "/" +
                  (date.getMonth() + 1) + "/" +
                  date.getFullYear() + " " +
                  date.getHours() + ":" + date.getMinutes() + ":" + date.getSeconds();
        }
        if (e === null || e === undefined) {
            console.log("Unknown error");
        } else {
            console.log(msg + " : " + e);
            console.log((e.stack ? e.stack : e));
        }
    }
}


/**
 * Load image or complete the given image loading.
 * @param  {String|Image} ph path or image to complete loading.
 * @param  {Boolean} [fireErr] flag to force or preserve error firing.
 * @return {zebkit.DoIt}
 * @method image
 * @for  zebkit
 */
function image(ph, fireErr) {
    if (arguments.length < 2) {
        fireErr = false;
    }
    var doit   = new DoIt(),
        jn     = doit.join(),
        marker = "data:image";

    if (isString(ph) && ph.length > marker.length) {
        // use "for" instead of "indexOf === 0"
        var i = 0;
        for(; i < marker.length && marker[i] === ph[i]; i++) {}

        if (i < marker.length) {
            var file = ZFS.read(ph);
            if (file !== null) {
                ph = "data:image/" + file.ext +  ";base64," + file.data;
            }
        }
    }

    $zenv.loadImage(ph,
        function(img) {
            jn(img);
        },
        function(img, e) {
            if (fireErr === true) {
                doit.error(e);
            } else {
                jn(img);
            }
        }
    );
    return doit;
}

//  Faster match operation analogues:
//  Math.floor(f)  =>  ~~(a)
//  Math.round(f)  =>  (f + 0.5) | 0

/**
 * Check if the given value is string
 * @param {Object} v a value.
 * @return {Boolean} true if the given value is string
 * @method isString
 * @for zebkit
 */
function isString(o)  {
    return o !== undefined && o !== null &&
          (typeof o === "string" || o.constructor === String);
}

/**
 * Check if the given value is number
 * @param {Object} v a value.
 * @return {Boolean} true if the given value is number
 * @method isNumber
 * @for zebkit
 */
function isNumber(o)  {
    return o !== undefined && o !== null &&
          (typeof o === "number" || o.constructor === Number);
}

/**
 * Check if the given value is boolean
 * @param {Object} v a value.
 * @return {Boolean} true if the given value is boolean
 * @method isBoolean
 * @for zebkit
 */
function isBoolean(o) {
    return o !== undefined && o !== null &&
          (typeof o === "boolean" || o.constructor === Boolean);
}

/**
 * Test if the given value has atomic type (String, Number or Boolean).
 * @param  {Object}  v a value
 * @return {Boolean} true if the value has atomic type
 * @method  isAtomic
 * @for zebkit
 */
function isAtomic(v) {
    return v === null || v === undefined ||
           (typeof v === "string"  || v.constructor === String)  ||
           (typeof v === "number"  || v.constructor === Number)  ||
           (typeof v === "boolean" || v.constructor === Boolean)  ;
}


Number.isInteger = Number.isInteger || function(value) {
    return typeof value === "number" &&
           isFinite(value) &&
           Math.floor(value) === value;
};


/**
 * Get property value for the given object and the specified property path
 * @param  {Object} obj  a target object.
 * as the target object
 * @param  {String} path property path. Use "`*" as path to collect all available public
 * properties.
 * @param  {Boolean} [useGetter] says too try getter method when it exists.
 * By default the parameter is false
 * @return {Object} a property value, return undefined if property cannot
 * be found
 * @method  getPropertyValue
 * @for  zebkit
 */
function getPropertyValue(obj, path, useGetter) {
    // if (arguments.length < 3) {
    //     useGetter = false;
    // }

    path = path.trim();
    if (path === undefined || path.length === 0) {
        throw new Error("Invalid field path: '" + path + "'");
    }

    // if (obj === undefined || obj === null) {
    //     throw new Error("Undefined target object");
    // }

    var paths = null,
        m     = null,
        p     = null;

    if (path.indexOf('.') > 0) {
        paths = path.split('.');

        for(var i = 0; i < paths.length; i++) {
            p = paths[i];

            if (obj !== undefined && obj !== null &&
                ((useGetter === true && (m = getPropertyGetter(obj, p))) || obj.hasOwnProperty(p)))
            {
                if (useGetter === true && m !== null) {
                    obj = m.call(obj);
                } else {
                    obj = obj[p];
                }
            } else {
                return undefined;
            }
        }
    } else if (path === '*') {
        var res = {};
        for (var k in obj) {
            if (k[0] !== '$' && obj.hasOwnProperty(k)) {
                res[k] = getPropertyValue(obj, k, useGetter === true);
            }
        }
        return res;
    } else {
        if (useGetter === true) {
            m = getPropertyGetter(obj, path);
            if (m !== null) {
                return m.call(obj);
            }
        }

        if (obj.hasOwnProperty(path) === true) {
            obj = obj[path];
        } else {
            return undefined;
        }
    }

    // detect object value factory
    if (obj !== null && obj !== undefined && obj.$new !== undefined) {
        return obj.$new();
    } else {
        return obj;
    }
}

/**
 * Get a property setter method if it is declared with the class of the specified object for the
 * given property. Setter is a method whose name matches the following pattern: "set<PropertyName>"
 * where the first letter of the property name is in upper case. For instance setter method for
 * property "color" has to have name "setColor".
 * @param  {Object} obj an object instance
 * @param  {String} name a property name
 * @return {Function}  a method that can be used as a setter for the given property
 * @method  getPropertySetter
 * @for zebkit
 */
function getPropertySetter(obj, name) {
    var pi = obj.constructor.$propertySetterInfo,
        m  = null;

    if (pi !== undefined) {
        if (pi[name] === undefined) {
            m = obj[ "set" + name[0].toUpperCase() + name.substring(1) ];
            pi[name] = (typeof m  === "function") ? m : null;
        }
        return pi[name];
    } else {
        // if this is not a zebkit class
        m = obj[ "set" + name[0].toUpperCase() + name.substring(1) ];
        return (typeof m  === "function") ? m : null;
    }
}

/**
 * Get a property getter method if it is declared with the class of the specified object for the
 * given property. Getter is a method whose name matches the following patterns: "get<PropertyName>"
 * or "is<PropertyName>" where the first letter of the property name is in upper case. For instance
 * getter method for property "color" has to have name "getColor".
 * @param  {Object} obj an object instance
 * @param  {String} name a property name
 * @return {Function}  a method that can be used as a getter for the given property
 * @method  getPropertyGetter
 * @for zebkit
 */
function getPropertyGetter(obj, name) {
    var pi = obj.constructor.$propertyGetterInfo,
        m  = null,
        suffix = null;

    if (pi !== undefined) {
        if (pi[name] === undefined) {
            suffix = name[0].toUpperCase() + name.substring(1);
            m  = obj[ "get" + suffix];
            if (typeof m !== 'function') {
                m = obj[ "is" + suffix];
            }
            pi[name] = (typeof m  === "function") ? m : null;
        }
        return pi[name];
    } else {
        suffix = name[0].toUpperCase() + name.substring(1);
        m      = obj[ "get" + suffix];
        if (typeof m !== 'function') {
            m = obj[ "is" + suffix];
        }
        return (typeof m === 'function') ? m : null;
    }
}

/**
 * Populate the given target object with the properties set. The properties set
 * is a dictionary that keeps properties names and its corresponding values.
 * Applying of the properties to an object does the following:
 *
 *
 *   - Detects if a property setter method exits and call it to apply
 *     the property value. Otherwise property is initialized as a field.
 *     Setter method is a method that matches "set<PropertyName>" pattern.
 *
 *   - Ignores properties whose names start from "$" character, equals "clazz"
 *     and properties whose values are function.
 *
 *   - Remove properties from the target object for properties that start from "-"
 *     character.
 *
 *   - Uses factory "$new" method to create a property value if the method can be
 *     detected in the property value.
 *
 *   - Apply properties recursively for properties whose names end with '/'
 *     character.
 *
 *
 * @param  {Object} target a target object
 * @param  {Object} props  a properties set
 * @return {Object} an object with the populated properties set.
 * @method  properties
 * @for  zebkit
 */
function properties(target, props) {
    for(var k in props) {
        // skip private properties( properties that start from "$")
        if (k !== "clazz" && k[0] !== '$' && props.hasOwnProperty(k) && props[k] !== undefined && typeof props[k] !== 'function') {
            if (k[0] === '-') {
                delete target[k.substring(1)];
            } else {
                var pv        = props[k],
                    recursive = k[k.length - 1] === '/',
                    tv        = null;

                // value factory detected
                if (pv !== null && pv.$new !== undefined) {
                    pv = pv.$new();
                }

                if (recursive === true) {
                    k = k.substring(0, k.length - 1);
                    tv = target[k];

                    // it is expected target value can be traversed recursively
                    if (pv !== null && (tv === null || tv === undefined || !(tv instanceof Object))) {
                        throw new Error("Target value is null, undefined or not an object. '" +
                                         k + "' property cannot be applied as recursive");
                    }
                } else {
                    tv = target[k];
                }

                if (recursive === true) {
                    if (pv === null) { // null value can be used to flush target value
                        target[k] = pv;
                    } else if (tv.properties !== undefined) {
                        tv.properties(pv); // target value itself has properties method
                    } else {
                        properties(tv, pv);
                    }
                } else {
                    var m = getPropertySetter(target, k);
                    if (m === null) {
                        target[k] = pv;  // setter doesn't exist, setup it as a field
                    } else {
                        // property setter is detected, call setter to
                        // set the property value
                        if (Array.isArray(pv)) {
                            m.apply(target, pv);
                        } else {
                            m.call(target, pv);
                        }
                    }
                }
            }
        }
    }
    return target;
}

// ( (http) :// (host)? (:port)? (/)? )? (path)? (?query_string)?
//
//  [1] scheme://host/
//  [2] scheme
//  [3] host
//  [4]  port
//  [5] /
//  [6] path
//  [7] ?query_string
//
var $uriRE = /^(([a-zA-Z]+)\:\/\/([^\/:]+)?(\:[0-9]+)?(\/)?)?([^?]+)?(\?.+)?/;

/**
 * URI class. Pass either a full uri (as a string or zebkit.URI) or number of an URI parts
 * (scheme, host, etc) to construct it.
 * @param {String} [uri] an URI.
 * @param {String} [scheme] a scheme.
 * @param {String} [host] a host.
 * @param {String|Integer} [port] a port.
 * @param {String} [path] a path.
 * @param {String} [qs] a query string.
 * @constructor
 * @class zebkit.URI
 */
function URI(uri) {
    if (arguments.length > 1) {
        if (arguments[0] !== null) {
            this.scheme = arguments[0].toLowerCase();
        }

        if (arguments[1] !== null) {
            this.host = arguments[1];
        }

        var ps = false;
        if (arguments.length > 2) {
            if (isNumber(arguments[2])) {
                this.port = arguments[2];
            } else if (arguments[2] !== null) {
                this.path = arguments[2];
                ps = true;
            }
        }

        if (arguments.length > 3) {
            if (ps === true) {
                this.qs = arguments[3];
            } else {
                this.path = arguments[3];
            }
        }

        if (arguments.length > 4) {
            this.qs = arguments[4];
        }
    } else if (uri instanceof URI) {
        this.host   = uri.host;
        this.path   = uri.path;
        this.qs     = uri.qs;
        this.port   = uri.port;
        this.scheme = uri.scheme;
    } else {
        if (uri === null || uri.trim().length === 0) {
            throw new Error("Invalid empty URI");
        }

        var m = uri.match($uriRE);
        if (m === null) {
            throw new Error("Invalid URI '" + uri + "'");
        }

        // fetch scheme
        if (m[1] !== undefined) {
            this.scheme = m[2].toLowerCase();

            if (m[3] === undefined) {
                if (this.scheme !== "file") {
                    throw new Error("Invalid host name : '" + uri + "'");
                }
            } else {
                this.host = m[3];
            }

            if (m[4] !== undefined) {
                this.port = parseInt(m[4].substring(1), 10);
            }
        }

        // fetch path
        if (m[6] !== undefined) {
            this.path = m[6];
        } else if (m[1] !== undefined) {
            this.path = "/";
        }

        if (m[7] !== undefined && m[7].length > 1) {
            this.qs = m[7].substring(1).trim();
        }
    }

    if (this.path !== null) {
        this.path = URI.normalizePath(this.path);

        if ((this.host !== null || this.scheme !== null) && this.path[0] !== '/') {
            this.path = "/" + this.path;
        }
    }

    if (this.scheme !== null) {
        this.scheme = this.scheme.toLowerCase();
    }

    if (this.host !== null) {
        this.host = this.host.toLowerCase();
    }

    /**
     * URI path.
     * @attribute path
     * @type {String}
     * @readOnly
     */

    /**
     * URI host.
     * @attribute host
     * @type {String}
     * @readOnly
     */

    /**
     * URI port number.
     * @attribute port
     * @type {Integer}
     * @readOnly
     */

    /**
     * URI query string.
     * @attribute qs
     * @type {String}
     * @readOnly
     */

     /**
      * URI scheme (e.g. 'http', 'ftp', etc).
      * @attribute scheme
      * @type {String}
      * @readOnly
      */
}

URI.prototype = {
    scheme   : null,
    host     : null,
    port     : -1,
    path     : null,
    qs       : null,

    /**
     * Serialize URI to its string representation.
     * @method  toString
     * @return {String} an URI as a string.
     */
    toString : function() {
        return (this.scheme !== null ? this.scheme + "://" : '') +
               (this.host !== null ? this.host : '' ) +
               (this.port !== -1   ? ":" + this.port : '' ) +
               (this.path !== null ? this.path : '' ) +
               (this.qs   !== null ? "?" + this.qs : '' );
    },

    /**
     * Get a parent URI.
     * @method getParent
     * @return {zebkit.URI} a parent URI.
     */
    getParent : function() {
        if (this.path === null) {
            return null;
        } else {
            var i = this.path.lastIndexOf('/');
            return (i < 0 || this.path === '/') ? null
                                                : new URI(this.scheme,
                                                          this.host,
                                                          this.port,
                                                          this.path.substring(0, i),
                                                          this.qs);
        }
    },

    /**
     * Append the given parameters to a query string of the URI.
     * @param  {Object} obj a dictionary of parameters to be appended to
     * the URL query string
     * @method appendQS
     */
    appendQS : function(obj) {
        if (obj !== null) {
            if (this.qs === null) {
                this.qs = '';
            }

            if (this.qs.length > 0) {
                this.qs = this.qs + "&" + URI.toQS(obj);
            } else {
                this.qs = URI.toQS(obj);
            }
        }
    },

    /**
     * Test if the URI is absolute.
     * @return {Boolean} true if the URI is absolute.
     * @method isAbsolute
     */
    isAbsolute : function() {
        return URI.isAbsolute(this.toString());
    },

    /**
     * Join URI with the specified path
     * @param  {String} p* relative paths
     * @return {String} an absolute URI
     * @method join
     */
    join : function() {
        var args = Array.prototype.slice.call(arguments);
        args.splice(0, 0, this.toString());
        return URI.join.apply(URI, args);
    },

    /**
     * Test if the given URL is file path.
     * @return {Boolean} true if the URL is file path
     * @method isFilePath
     */
    isFilePath : function() {
        return this.scheme === null || this.scheme === 'file';
    },

    /**
     * Get an URI relative to the given URI.
     * @param  {String|zebkit.URI} to an URI to that the relative URI has to be detected.
     * @return {String} a relative URI
     * @method relative
     */
    relative : function(to) {
        if ((to instanceof URI) === false) {
            to = new URI(to);
        }

        if (this.isAbsolute()                                                      &&
            to.isAbsolute()                                                        &&
            this.host === to.host                                                  &&
            this.port === to.port                                                  &&
            (this.scheme === to.scheme || (this.isFilePath() && to.isFilePath()) ) &&
            (this.path.indexOf(to.path) === 0 && (to.path.length === this.path.length ||
                                                  (to.path.length === 1 && to.path[0] === '/') ||
                                                  this.path[to.path.length] ===  '/'     )))
        {
            return (to.path.length === 1 && to.path[0] === '/') ? this.path.substring(to.path.length)
                                                                : this.path.substring(to.path.length + 1);
        } else {
            return null;
        }
    }
};

/**
 * Test if the given string is absolute path or URI.
 * @param  {String|zebkit.URI}  u an URI
 * @return {Boolean} true if the string is absolute path or URI.
 * @method isAbsolute
 * @static
 */
URI.isAbsolute = function(u) {
    return u[0] === '/' || /^[a-zA-Z]+\:\/\//i.test(u);
};

/**
 * Test if the given string is URL.
 * @param  {String|zebkit.URI}  u a string to be checked.
 * @return {Boolean} true if the string is URL
 * @method isURL
 * @static
 */
URI.isURL = function(u) {
    return /^[a-zA-Z]+\:\/\//i.test(u);
};

/**
 * Get a relative path.
 * @param  {String|zebkit.URI} base a base path
 * @param  {String|zebkit.URI} path a path
 * @return {String} a relative path
 * @method relative
 * @static
 */
URI.relative = function(base, path) {
    if ((path instanceof URI) === false) {
        path = new URI(path);
    }
    return path.relative(base);
};

/**
 * Parse the specified query string of the given URI.
 * @param  {String|zebkit.URI} url an URI
 * @param  {Boolean} [decode] pass true if query string has to be decoded.
 * @return {Object} a parsed query string as a dictionary of parameters
 * @method parseQS
 * @static
 */
URI.parseQS = function(qs, decode) {
    if (qs instanceof URI) {
        qs = qs.qs;
        if (qs === null) {
            return null;
        }
    } else if (qs[0] === '?') {
        qs = qs.substring(1);
    }

    var mqs      = qs.match(/[a-zA-Z0-9_.]+=[^?&=]+/g),
        parsedQS = {};

    if (mqs !== null) {
        for(var i = 0; i < mqs.length; i++) {
            var q = mqs[i].split('='),
                k = q[0].trim(),
                v = decode === true ? $zenv.decodeURIComponent(q[1])
                                    : q[1];

            if (parsedQS.hasOwnProperty(k)) {
                var p = parsedQS[k];
                if (Array.isArray(p) === false) {
                    parsedQS[k] = [ p ];
                }
                parsedQS[k].push(v);
            } else {
                parsedQS[k] = v;
            }
        }
    }
    return parsedQS;
};


URI.decodeQSValue = function(value) {
    if (Array.isArray(value)) {
        var r = [];
        for(var i = 0; i < value.length; i++) {
            r[i] = URI.decodeQSValue(value[i]);
        }
        return r;
    } else {
        value = value.trim();
        if (value[0] === "'") {
            value = value.substring(1, value.length - 1);
        } else if (value === "true" || value === "false") {
            value = (value === "true");
        } else if (value === "null") {
            value = null;
        } else if (value === "undefined") {
            value = undefined;
        } else {
            var num = (value.indexOf('.') >= 0) ? parseFloat(value)
                                                : parseInt(value, 10);
            if (isNaN(num) === false) {
                value = num;
            }
        }
        return value;
    }
};

URI.normalizePath = function(p) {
    if (p !== null && p.length > 0) {
        p = p.trim().replace(/[\\]+/g, '/');
        for (; ; ) {
            var len = p.length;
            p = p.replace(/[^./]+[/]+\.\.[/]+/g, '');
            p = p.replace(/[\/]+/g, '/');
            if (p.length == len) {
                break;
            }
        }

        var l = p.length;
        if (l > 1 && p[l - 1] === '/') {
            p = p.substring(0, l - 1);
        }
    }

    return p;
};

/**
 * Convert the given dictionary of parameters to a query string.
 * @param  {Object} obj a dictionary of parameters
 * @param  {Boolean} [encode] pass true if the parameters values have to be
 * encoded
 * @return {String} a query string built from parameters list
 * @static
 * @method toQS
 */
URI.toQS = function(obj, encode) {
    if (isString(obj) || isBoolean(obj) || isNumber(obj)) {
        return "" + obj;
    }

    var p = [];
    for(var k in obj) {
        if (obj.hasOwnProperty(k)) {
            p.push(k + '=' + (encode === true ? $zenv.encodeURIComponent(obj[k].toString())
                                              : obj[k].toString()));
        }
    }
    return p.join("&");
};

/**
 * Join the given  paths
 * @param  {String|zebkit.URI} p* relative paths
 * @return {String} a joined path as string
 * @method join
 * @static
 */
URI.join = function() {
    if (arguments.length === 0) {
        throw new Error("No paths to join");
    }

    var uri = new URI(arguments[0]);
    for(var i = 1; i < arguments.length; i++) {
        var p = arguments[i];

        if (p === null || p.length === 0) {
            throw new Error("Empty sub-path is not allowed");
        }

        if (URI.isAbsolute(p)) {
            throw new Error("Absolute path '" + p + "' cannot be joined");
        }

        if (p instanceof URI) {
            p = arguments[i].path;
        } else {
            p = new URI(p).path;
        }

        if (p.length === 0) {
            throw new Error("Empty path cannot be joined");
        }

        uri.path = uri.path + (uri.path === '/' ? '' : "/") + p;
    }

    uri.path = URI.normalizePath(uri.path);
    return uri.toString();
};

$export(
    URI,        isNumber, isString, isAtomic,
    dumpError,  image,    getPropertySetter,
    getPropertyValue,     getPropertyGetter,
    properties, GET,      isBoolean, DoIt,
    { "$global"    : $global,
      "$FN"        : $FN,
      "ZFS"        : ZFS,
      "environment": $zenv,
      "isIE"       : isIE,
      "isFF"       : isFF,
      "isMacOS"    : isMacOS }
);



var $$$        = 11,   // hash code counter
    $caller    = null, // currently called method reference
    $cachedO   = {},   // class cache
    $cachedE   = [],
    $cacheSize = 7777,
    CNAME      = '$',
    CDNAME     = '';

function $toString() {
    return this.$hash$;
}

function $ProxyMethod(name, f, clazz) {
    if (f.methodBody !== undefined) {
        throw new Error("Proxy method '" + name + "' cannot be wrapped");
    }

    var a = function() {
        var cm = $caller;
        $caller = a;
        // don't use finally section it is slower than try-catch
        try {
            var r = f.apply(this, arguments);
            $caller = cm;
            return r;
        } catch(e) {
            $caller = cm;
            console.log(name + "(" + arguments.length + ") " + (e.stack ? e.stack : e));
            throw e;
        }
    };

    a.methodBody = f;
    a.methodName = name;
    a.boundTo    = clazz;
    return a;
}

/**
 * Get an object by the given key from cache (and cached it if necessary)
 * @param  {String} key a key to an object. The key is hierarchical reference starting with the global
 * name space as root. For instance "test.a" key will fetch $global.test.a object.
 * @return {Object}  an object
 * @for  zebkit
 * @private
 * @method  $cache
 */
function $cache(key) {
    if ($cachedO.hasOwnProperty(key) === true) {
        // read cached entry
        var e = $cachedO[key];
        if (e.i < ($cachedE.length-1)) { // cached entry is not last one

            // move accessed entry to the list tail to increase its access weight
            var pn = $cachedE[e.i + 1];
            $cachedE[e.i]   = pn;
            $cachedE[++e.i] = key;
            $cachedO[pn].i--;
        }
        return e.o;
    }

    // don't cache global objects
    if ($global.hasOwnProperty(key)) {
        return $global[key];
    }

    var ctx = $global, i = 0, j = 0;
    for( ;ctx !== null && ctx !== undefined; ) {
        i = key.indexOf('.', j);

        if (i < 0) {
            ctx = ctx[key.substring(j, key.length)];
            break;
        }

        ctx = ctx[key.substring(j, i)];
        j = i + 1;
    }

    if (ctx !== null && ctx !== undefined) {
        if ($cachedE.length >= $cacheSize) {
            // cache is full, replace first element with the new one
            var n = $cachedE[0];
            $cachedE[0]   = key;
            $cachedO[key] = { o: ctx, i: 0 };
            delete $cachedO[n];
        } else {
            $cachedO[key] = { o: ctx, i: $cachedE.length };
            $cachedE[$cachedE.length] = key;
        }
        return ctx;
    }

    throw new Error("Reference '" + key + "' not found");
}

// copy methods from source to destination
function $cpMethods(src, dest, clazz) {
    var overriddenAbstractMethods = 0;
    for(var name in src) {
        if (name   !==  CNAME        &&
            name   !== "clazz"       &&
            src.hasOwnProperty(name)   )
        {
            var method = src[name];
            if (typeof method === "function" && method !== $toString) {
                if (name === "$prototype") {
                    method.call(dest, clazz);
                } else {
                    // TODO analyze if we overwrite existent field
                    if (dest[name] !== undefined) {
                        // abstract method is overridden, let's skip abstract method
                        // stub implementation
                        if (method.$isAbstract === true) {
                            overriddenAbstractMethods++;
                            continue;
                        }

                        if (dest[name].boundTo === clazz) {
                            throw new Error("Method '" + name + "(...)'' bound to this class already exists");
                        }
                    }

                    if (method.methodBody !== undefined) {
                        dest[name] = $ProxyMethod(name, method.methodBody, clazz);
                    } else {
                        dest[name] = $ProxyMethod(name, method, clazz);
                    }

                    // save information about abstract method
                    if (method.$isAbstract === true) {
                        dest[name].$isAbstract = true;
                    }
                }
            }
        }
    }
    return overriddenAbstractMethods;
}

// return function that is meta class
//  instanceOf      - parent template function (can be null)
//  templateConstructor - template function,
//  inheritanceList     - parent class and interfaces
function $make_template(instanceOf, templateConstructor, inheritanceList) {
    // supply template with unique identifier that is returned with toString() method
    templateConstructor.$hash$   = "$zEk$" + ($$$++);
    templateConstructor.toString = $toString;
    templateConstructor.prototype.clazz = templateConstructor; // instances of the template has to point to the template as a class

    templateConstructor.clazz = templateConstructor.constructor = instanceOf;

    /**
     *  Unique string hash code. The property is not defined if the class was not
     *  maid hashable by calling "hashable()" method.
     *  @attribute $hash$
     *  @private
     *  @type {String}
     *  @for  zebkit.Class
     *  @readOnly
     */

    /**
     * Dictionary of all inherited interfaces where key is unique interface hash code and the value
     * is interface itself.
     * @private
     * @readOnly
     * @for zebkit.Class
     * @type {Object}
     * @attribute $parents
     * @type {Object}
     */
    templateConstructor.$parents = {};

    // instances of the constructor also has to be unique
    // so force toString method population
    templateConstructor.prototype.constructor = templateConstructor; // set constructor of instances to the template

    // setup parent entities
    if (arguments.length > 2 && inheritanceList.length > 0) {
        for(var i = 0; i < inheritanceList.length; i++) {
            var toInherit = inheritanceList[i];
            if (toInherit === undefined         ||
                toInherit === null              ||
                typeof toInherit !== "function" ||
                toInherit.$hash$ === undefined    )
            {
                throw new ReferenceError("Invalid parent class or interface:" + toInherit);
            }

            if (templateConstructor.$parents[toInherit.$hash$] !== undefined) {
                var inh = '<unknown>';

                // try to detect class or interface name
                if (toInherit !== null && toInherit !== undefined) {
                    if (toInherit.$name !== null && toInherit.$name !== undefined) {
                        inh = toInherit.$name;
                    } else {
                        inh = toInherit;
                    }
                }
                throw Error("Duplicated inheritance: " + toInherit );
            }

            templateConstructor.$parents[toInherit.$hash$] = toInherit;

            // if parent has own parents copy the parents references
            for(var k in toInherit.$parents) {
                if (templateConstructor.$parents[k] !== undefined) {
                    throw Error("Duplicate inherited class or interface: " + k);
                }

                templateConstructor.$parents[k] = toInherit.$parents[k];
            }
        }
    }
    return templateConstructor;
}

/**
 * Clone the given object. The method tries to perform deep cloning by
 * traversing the given object structure recursively. Any part of an
 * object can be marked as not cloneable by adding  "$notCloneable"
 * field that equals to true. Also at any level of object structure
 * the cloning can be customized with adding "$clone" method. In this
 * case the method will be used to clone the part of object.
 * clonable
 * @param  {Object} obj an object to be cloned
 * @return {Object} a cloned object
 * @method  clone
 * @for  zebkit
 */
function clone(obj, map) {
    // clone atomic type
    // TODO: to speedup cloning we don't use isString, isNumber, isBoolean
    if (obj === null || obj === undefined || obj.$notCloneable === true ||
                                            (typeof obj === "string"  || obj.constructor === String  ) ||
                                            (typeof obj === "boolean" || obj.constructor === Boolean ) ||
                                            (typeof obj === "number"  || obj.constructor === Number  )    )
    {
        return obj;
    }

    map = map || new Map();
    var t = map.get(obj);
    if (t !== undefined) {
        return t;
    }

    // clone with provided custom "clone" method
    if (obj.$clone !== undefined) {
        return obj.$clone(map);
    }

    // clone array
    if (Array.isArray(obj)) {
        var naobj = [];

        map.set(obj, naobj);
        map[obj] = naobj;

        for(var i = 0; i < obj.length; i++) {
            naobj[i] = clone(obj[i], map);
        }
        return naobj;
    }

    // clone class
    if (obj.clazz === Class) {
        var clazz = Class(obj, []);
        clazz.inheritProperties = true;
        return clazz;
    }

    // function cannot be cloned
    if (typeof obj === 'function' || obj.constructor !==  Object) {
        return obj;
    }

    var nobj = {};
    map.set(obj, nobj); // keep one instance of cloned for the same object

    // clone object fields
    for(var k in obj) {
        if (obj.hasOwnProperty(k) === true) {
            nobj[k] = clone(obj[k], map);
        }
    }

    return nobj;
}

/**
 * Instantiate a new class instance of the given class with the specified constructor
 * arguments.
 * @param  {Function} clazz a class
 * @param  {Array} [args] an arguments list
 * @return {Object}  a new instance of the given class initialized with the specified arguments
 * @method newInstance
 * @for  zebkit
 */
function newInstance(clazz, args) {
    if (arguments.length > 1 && args.length > 0) {
        var f = function () {};
        f.prototype = clazz.prototype;
        var o = new f();
        clazz.apply(o, args);
        return o;
    }

    return new clazz();
}

function $make_proto(props, superProto) {
    if (superProto === null) {
        return function $prototype(clazz) {
            for(var k in props) {
                if (props.hasOwnProperty(k)) {
                    this[k] = props[k];
                }
            }
        };
    } else {
        return function $prototype(clazz) {
            superProto.call(this, clazz);
            for(var k in props) {
                if (props.hasOwnProperty(k)) {
                    this[k] = props[k];
                }
            }
        };
    }
}

/**
 * Interface is way to share common functionality by avoiding multiple inheritance.
 * It allows developers to mix number of methods to different classes. For instance:

      // declare "I" interface that contains one method a
      var I = zebkit.Interface([
          function a() {

          }
      ]);

      // declare "A" class
      var A = zebkit.Class([]);

      // declare "B" class that inherits class A and mix interface "I"
      var B = zebkit.Class(A, I, []);

      // instantiate "B" class
      var b = new B();
      zebkit.instanceOf(b, I);  // true
      zebkit.instanceOf(b, A);  // true
      zebkit.instanceOf(b, B);  // true

      // call mixed method
      b.a();

 * @return {Function} an interface
 * @param {Array} [methods] list of methods declared in the interface
 * @constructor
 * @class  zebkit.Interface
 */
var Interface = $make_template(null, function() {
    var $Interface = $make_template(Interface, function() {
        // Clone interface  parametrized with the given properties set
        if (typeof this === 'undefined' || this.constructor !== $Interface) {  // means the method execution is not a result of "new" method
            if (arguments.length !== 1) {
                throw new Error("Invalid number of arguments. Properties set is expected");
            }

            if (arguments[0].constructor !== Object) {
                throw new Error("Invalid argument type. Properties set is expected");
            }

            var iclone = $Interface.$clone();
            iclone.prototype.$prototype = $make_proto(arguments[0],
                                                     $Interface.prototype.$prototype);
            return iclone;
        } else {
            // Create a class that inherits the interface and instantiate it
            if (arguments.length > 1) {
                throw new Error("One or zero argument is expected");
            }
            return new (Class($Interface, arguments.length > 0 ? arguments[0] : []))();
        }
    });

    if (arguments.length > 1) {
        throw new Error("Invalid number of arguments. List of methods or properties is expected");
    }

    // abstract method counter, not used now, but can be used in the future
    // to understand if the given class override all abstract methods (should be
    // controlled in the places of "$cpMethods" call)
    $Interface.$abstractMethods = 0;

    var arg = arguments.length === 0 ? [] : arguments[0];
    if (arg.constructor === Object) {
        arg = [ $make_proto(arg, null) ];
    } else if (Array.isArray(arg) === false) {
        throw new Error("Invalid argument type. List of methods pr properties is expected");
    }

    if (arg.length > 0) {
        var  proto      = $Interface.prototype,
             isAbstract = false;

        for(var i = 0; i < arg.length; i++) {
            var method = arg[i];

            if (method === "abstract") {
                isAbstract = true;
            } else {
                if (typeof method !== "function") {
                    throw new Error("Method is expected instead of " + method);
                }

                var name = $FN(method);
                if (name === CDNAME) {
                    throw new Error("Constructor declaration is not allowed in interface");
                }

                if (proto[name] !== undefined) {
                    throw new Error("Duplicated interface method '" + name + "(...)'");
                }

                if (name === "$clazz") {
                    method.call($Interface, $Interface);
                } else if (isAbstract === true) {
                    (function(name) {
                        proto[name] = function() {
                            throw new Error("Abstract method '" + name + "(...)' is not implemented");
                        };

                        // mark method as abstract
                        proto[name].$isAbstract = true;

                        // count abstract methods
                        $Interface.$abstractMethods++;
                    })(name);
                } else {
                    proto[name] = method;
                }
            }
        }
    }

    /**
     * Private implementation of an interface cloning.
     * @return {zebkit.Interface} a clone of the interface
     * @method $clone
     * @private
     */
    $Interface.$clone = function() {
        var iclone = Interface(), k = null; // create interface

        // clone interface level variables
        for(k in this) {
            if (this.hasOwnProperty(k)) {
                iclone[k] = clone(this[k]);
            }
        }

        // copy methods from proto
        var proto = this.prototype;
        for(k in proto) {
            if (k !== "clazz" && proto.hasOwnProperty(k) === true) {
                iclone.prototype[k] = clone(proto[k]);
            }
        }

        return iclone;
    };

    $Interface.clazz.$name = "zebkit.Interface"; // assign name
    return $Interface;
});

/**
 * Core method method to declare a zebkit class following easy OOP approach. The easy OOP concept
 * supports the following OOP features:
 *
 *
 *  __Single class inheritance.__ Any class can extend an another zebkit class

        // declare class "A" that with one method "a"
        var A = zebkit.Class([
            function a() { ... }
        ]);

        // declare class "B" that inherits class "A"
        var B = zebkit.Class(A, []);

        // instantiate class "B" and call method "a"
        var b = new B();
        b.a();


* __Class method overriding.__ Override a parent class method implementation

        // declare class "A" that with one method "a"
        var A = zebkit.Class([
            function a() { ... }
        ]);

        // declare class "B" that inherits class "A"
        // and overrides method a with an own implementation
        var B = zebkit.Class(A, [
            function a() { ... }
        ]);

* __Constructors.__ Constructor is a method with empty name

        // declare class "A" that with one constructor
        var A = zebkit.Class([
            function () { this.variable = 100; }
        ]);

        // instantiate "A"
        var a = new A();
        a.variable // variable is 100

* __Static methods and variables declaration.__ Static fields and methods can be defined
    by declaring special "$clazz" method whose context is set to declared class

        var A = zebkit.Class([
            // special method where static stuff has to be declared
            function $clazz() {
                // declare static field
                this.staticVar = 100;
                // declare static method
                this.staticMethod = function() {};
            }
        ]);

        // access static field an method
        A.staticVar      // 100
        A.staticMethod() // call static method

* __Access to super class context.__ You can call method declared in a parent class

        // declare "A" class with one class method "a(p1,p2)"
        var A = zebkit.Class([
            function a(p1, p2) { ... }
        ]);

        // declare "B" class that inherits "A" class and overrides "a(p1,p2)" method
        var B = zebkit.Class(A, [
            function a(p1, p2) {
                // call "a(p1,p2)" method implemented with "A" class
                this.$super(p1,p2);
            }
        ]);

 *
 *  One of the powerful feature of zebkit easy OOP concept is possibility to instantiate
 *  anonymous classes and interfaces. Anonymous class is an instance of an existing
 *  class that can override the original class methods with own implementations, implements
 *  own list of interfaces and methods. In other words the class instance customizes class
 *  definition for the particular instance of the class;

        // declare "A" class
        var A = zebkit.Class([
            function a() { return 1; }
        ]);

        // instantiate anonymous class that add an own implementation of "a" method
        var a = new A([
            function a() { return 2; }
        ]);
        a.a() // return 2

 * @param {zebkit.Class} [inheritedClass] an optional parent class to be inherited
 * @param {zebkit.Interface} [inheritedInterfaces]* an optional list of interfaces for
 * the declared class to be mixed in the class
 * @param {Array} methods list of declared class methods. Can be empty array.
 * @return {Function} a class definition
 * @constructor
 * @class zebkit.Class
 */
function $mixing(clazz, methods) {
    if (Array.isArray(methods) === false) {
        throw new Error("Methods array is expected (" + methods + ")");
    }

    var names = {};
    for(var i = 0; i < methods.length; i++) {
        var method     = methods[i],
            methodName = $FN(method);

        // detect if the passed method is proxy method
        if (method.methodBody !== undefined) {
            throw new Error("Proxy method '" + methodName + "' cannot be mixed in a class");
        }

        // map user defined constructor to internal constructor name
        if (methodName === CDNAME) {
            methodName = CNAME;
        } else if (methodName[0] === '$') {
            // populate prototype fields if a special method has been defined
            if (methodName === "$prototype") {
                method.call(clazz.prototype, clazz);
                if (clazz.prototype[CDNAME]) {
                    clazz.prototype[CNAME] = clazz.prototype[CDNAME];
                    delete clazz.prototype[CDNAME];
                }
                continue;
            }

            // populate class level fields if a special method has been defined
            if (methodName === "$clazz") {
                method.call(clazz);
                continue;
            }
        }

        if (names[methodName] === true) {
            throw new Error("Duplicate declaration of '" + methodName+ "(...)' method");
        }

        var existentMethod = clazz.prototype[methodName];
        if (existentMethod !== undefined && typeof existentMethod !== 'function') {
            throw new Error("'" + methodName + "(...)' method clash with a field");
        }

        // if constructor doesn't have super definition than let's avoid proxy method
        // overhead
        if (existentMethod === undefined && methodName === CNAME) {
            clazz.prototype[methodName] = method;
        } else {
            // Create and set proxy method that is bound to the given class
            clazz.prototype[methodName] = $ProxyMethod(methodName, method, clazz);
        }

        // save method we have already added to check double declaration error
        names[methodName] = true;
    }
}

// Class methods to be populated in all classes
var classTemplateFields = {
    /**
     * Makes the class hashable. Hashable class instances are automatically
     * gets unique hash code that is returned with its overridden "toString()"
     * method. The hash code is stored in special "$hash$" field. The feature
     * can be useful when you want to store class instances in "{}" object
     * where key is the hash and the value is the instance itself.
     * @method hashable
     * @chainable
     * @for zebkit.Class
     */
    hashable : function() {
        if (this.$uniqueness !== true) {
            this.$uniqueness = true;
            this.prototype.toString = $toString;
        }
        return this;
    },

    /**
     * Makes the class hashless. Prevents generation of hash code for
     * instances of the class.
     * @method hashless
     * @chainable
     * @for zebkit.Class
     */
    hashless : function() {
        if (this.$uniqueness === true) {
            this.$uniqueness = false;
            this.prototype.toString = Object.prototype.toString;
        }
        return this;
    },

    /**
     * Extend the class with new method and implemented interfaces.
     * @param {zebkit.Interface} [interfaces]*  number of interfaces the class has to implement.
     * @param {Array} methods set of methods the given class has to be extended.
     * @method extend
     * @chainable
     * @for zebkit.Class
     */
    // add extend method later to avoid the method be inherited as a class static field
    extend : function() {
        var methods   = arguments[arguments.length - 1],
            hasMethod = Array.isArray(methods);

        // inject class
        if (hasMethod && this.$isExtended !== true) {
            // create intermediate class
            var A = this.$parent !== null ? Class(this.$parent, [])
                                          : Class([]);

            // copy this class prototypes methods to intermediate class A and re-define
            // boundTo to the intermediate class A if they were bound to source class
            // methods that have been  moved from source class to class have to be re-bound
            // to A class
            for(var name in this.prototype) {
                if (name !== "clazz" && this.prototype.hasOwnProperty(name) ) {
                    var f = this.prototype[name];
                    if (typeof f === 'function') {
                        A.prototype[name] = f.methodBody !== undefined ? $ProxyMethod(name, f.methodBody, f.boundTo)
                                                                       : f;

                        if (A.prototype[name].boundTo === this) {
                            A.prototype[name].boundTo = A;
                            if (f.boundTo === this) {
                                f.boundTo = A;
                            }
                        }
                    }
                }
            }

            this.$parent = A;
            this.$isExtended = true;
        }

        if (hasMethod) {
            $mixing(this, methods);
        }

        // add passed interfaces
        for(var i = 0; i < arguments.length - (hasMethod ? 1 : 0); i++) {
            var I = arguments[i];
            if (I === null || I === undefined || I.clazz !== Interface) {
                throw new Error("Interface is expected");
            }

            if (this.$parents[I.$hash$] !== undefined) {
                throw new Error("Interface has been already inherited");
            }

            $cpMethods(I.prototype, this.prototype, this);
            this.$parents[I.$hash$] = I;
        }

        return this;
    },

    /**
     * Tests if the class inherits the given class or interface.
     * @param  {zebkit.Class | zebkit.Interface} clazz a class or interface.
     * @return {Boolean} true if the class or interface is inherited with
     * the class.
     * @method  isInherit
     * @for  zebkit.Class
     */
    isInherit : function(clazz) {
        if (this !== clazz) {
            // detect class
            if (clazz.clazz === this.clazz) {
                for (var p = this.$parent; p !== null; p = p.$parent) {
                    if (p === clazz) {
                        return true;
                    }
                }
            } else { // detect interface
                if (this.$parents[clazz.$hash$] === clazz) {
                    return true;
                }
            }
        }
        return false;
    },

    /**
     * Create an instance of the class
     * @param  {Object} [arguments]* arguments to be passed to the class constructor
     * @return {Object} an instance of the class.
     * @method newInstance
     * @for  zebkit.Class
     */
    newInstance : function() {
        return arguments.length === 0 ? newInstance(this)
                                      : newInstance(this, arguments);
    },

    /**
     * Create an instance of the class
     * @param  {Array} args an arguments array
     * @return {Object} an instance of the class.
     * @method newInstancea
     * @for  zebkit.Class
     */
    newInstancea : function(args) {
        return arguments.length === 0 ? newInstance(this)
                                      : newInstance(this, args);
    }
};

// methods are populated in all instances of zebkit classes
var classTemplateProto = {
    /**
     * Extend existent class instance with the given methods and interfaces
     * For example:

        var A = zebkit.Class([ // declare class A that defines one "a" method
            function a() {
                console.log("A:a()");
            }
        ]);

        var a = new A();
        a.a();  // show "A:a()" message

        A.a.extend([
            function b() {
                console.log("EA:b()");
            },

            function a() {   // redefine "a" method
                console.log("EA:a()");
            }
        ]);

        a.b(); // show "EA:b()" message
        a.a(); // show "EA:a()" message

     * @param {zebkit.Interface} [interfaces]* interfaces to be implemented with the
     * class instance
     * @param {Array} methods list of methods the class instance has to be extended
     * with
     * @method extend
     * @for zebkit.Class.zObject
     */
    extend : function() {
        var clazz = this.clazz,
            l = arguments.length,
            f = arguments[l - 1],
            hasArray = Array.isArray(f),
            i = 0;

        // replace the instance class with a new intermediate class
        // that inherits the replaced class. it is done to support
        // $super method calls.
        if (this.$isExtended !== true) {
            clazz = Class(clazz, []);
            this.$isExtended = true;         // mark the instance as extended to avoid double extending.
            clazz.$name = this.clazz.$name;
            this.clazz = clazz;
        }

        if (hasArray) {
            var init = null;
            for(i = 0; i < f.length; i++) {
                var n = $FN(f[i]);
                if (n === CDNAME) {
                    init = f[i];  // postpone calling initializer before all methods will be defined
                } else {
                    if (this[n] !== undefined && typeof this[n] !== 'function') {
                        throw new Error("Method '" + n + "' clash with a property");
                    }
                    this[n] = $ProxyMethod(n, f[i], clazz);
                }
            }

            if (init !== null) {
                init.call(this);
            }
            l--;
        }

        // add new interfaces if they has been passed
        for (i = 0; i < arguments.length - (hasArray ? 1 : 0); i++) {
            if (arguments[i].clazz !== Interface) {
                throw new Error("Invalid argument " + arguments[i] + " Interface is expected.");
            }

            var I = arguments[i];
            if (clazz.$parents[I.$hash$] !== undefined) {
                throw new Error("Interface has been already inherited");
            }

            $cpMethods(I.prototype, this, clazz);
            clazz.$parents[I.$hash$] = I;
        }
        return this;
    },

    /**
     * Call super method implementation.
     * @param {Function} [superMethod]? optional parameter that should be a method of the class instance
     * that has to be called
     * @param {Object} [args]* arguments list to pass the executed method
     * @return {Object} return what super method returns
     * @method $super
     * @example
     *
     *    var A = zebkit.Class([
     *        function a(p) { return 10 + p; }
     *    ]);
     *
     *    var B = zebkit.Class(A, [
     *        function a(p) {
     *            return this.$super(p) * 10;
     *        }
     *    ]);
     *
     *    var b = new B();
     *    b.a(10) // return 200
     *
     * @for zebkit.Class.zObject
     */
    $super : function() {
       if ($caller !== null) {
            for (var $s = $caller.boundTo.$parent; $s !== null; $s = $s.$parent) {
                var m = $s.prototype[$caller.methodName];
                if (m !== undefined) {
                    return m.apply(this, arguments);
                }
            }

            // handle method not found error
            var cln = this.clazz && this.clazz.$name ? this.clazz.$name + "." : "";
            throw new ReferenceError("Method '" +
                                     cln +
                                     ($caller.methodName === CNAME ? "constructor"
                                                                   : $caller.methodName) + "(" + arguments.length + ")" + "' not found");
        } else {
            throw new Error("$super is called outside of class context");
        }
    },

    // TODO: not stable API
    $supera : function(args) {
       if ($caller !== null) {
            for (var $s = $caller.boundTo.$parent; $s !== null; $s = $s.$parent) {
                var m = $s.prototype[$caller.methodName];
                if (m !== undefined) {
                    return m.apply(this, args);
                }
            }

            // handle method not found error
            var cln = this.clazz && this.clazz.$name ? this.clazz.$name + "." : "";
            throw new ReferenceError("Method '" +
                                     cln +
                                     ($caller.methodName === CNAME ? "constructor"
                                                                   : $caller.methodName) + "(" + arguments.length + ")" + "' not found");
        } else {
            throw new Error("$super is called outside of class context");
        }
    },

    // TODO: not stable API, $super that doesn't throw exception is there is no super implementation
    $$super : function() {
       if ($caller !== null) {
            for(var $s = $caller.boundTo.$parent; $s !== null; $s = $s.$parent) {
                var m = $s.prototype[$caller.methodName];
                if (m !== undefined) {
                    return m.apply(this, arguments);
                }
            }
        } else {
            throw new Error("$super is called outside of class context");
        }
    },

    /**
     * Get a first super implementation of the given method in a parent classes hierarchy.
     * @param  {String} name a name of the method
     * @return {Function} a super method implementation
     * @method  $getSuper
     * @for  zebkit.Class.zObject
     */
    $getSuper : function(name) {
       if ($caller !== null) {
            for(var $s = $caller.boundTo.$parent; $s !== null; $s = $s.$parent) {
                var m = $s.prototype[name];
                if (typeof m === 'function') {
                    return m;
                }
            }
            return null;
        }
        throw new Error("$super is called outside of class context");
    },

    $genHash : function() {
        if (this.$hash$ === undefined) {
            this.$hash$ = "$ZeInGen" + ($$$++);
        }
        return this.$hash$;
    },

    $clone : function(map) {
        map = map || new Map();

        var f = function() {};
        f.prototype = this.constructor.prototype;
        var nobj = new f();
        map.set(this, nobj);

        for(var k in this) {
            if (this.hasOwnProperty(k)) {
                // obj's layout is obj itself
                var t = map.get(this[k]);
                if (t !== undefined) {
                    nobj[k] = t;
                } else {
                    nobj[k] = clone(this[k], map);
                }
            }
        }

        // speed up clearing resources
        map.clear();

        nobj.constructor = this.constructor;

        if (nobj.$hash$ !== undefined) {
            nobj.$hash$ = "$zObj_" + ($$$++);
        }

        nobj.clazz = this.clazz;
        return nobj;
    }
};

// create Class template what means we define a function (meta class) that has to be used to define
// Class. That means we define a function that returns another function that is a Class
var Class = $make_template(null, function() {
    if (arguments.length === 0) {
        throw new Error("No class method list was found");
    }

    if (Array.isArray(arguments[arguments.length - 1]) === false) {
        throw new Error("No class methods have been passed");
    }

    if (arguments.length > 1 && typeof arguments[0] !== "function")  {
        throw new ReferenceError("Invalid parent class or interface '" + arguments[0] + "'");
    }

    var classMethods = arguments[arguments.length - 1],
        parentClass  = null,
        toInherit    = [];

    // detect parent class in inheritance list as the first argument that has "clazz" set to Class
    if (arguments.length > 0 && (arguments[0] === null || arguments[0].clazz === Class)) {
        parentClass = arguments[0];
    }

    // use instead of slice for performance reason
    for(var i = 0; i < arguments.length - 1; i++) {
        toInherit[i] = arguments[i];

        // let's make sure we inherit interface
        if (parentClass === null || i > 0) {
            if (toInherit[i] === undefined || toInherit[i] === null) {
                throw new ReferenceError("Undefined inherited interface [" + i + "] " );
            } else if (toInherit[i].clazz !== Interface) {
                throw new ReferenceError("Inherited interface is not an Interface ( [" + i + "] '" + toInherit[i] + "'')");
            }
        }
    }

    // define Class (function) that has to be used to instantiate the class instance
    var classTemplate = $make_template(Class, function() {
        if (classTemplate.$uniqueness === true) {
            this.$hash$ = "$ZkIo" + ($$$++);
        }

        if (arguments.length > 0) {
            var a = arguments[arguments.length - 1];

            // anonymous is customized class instance if last arguments is array of functions
            if (Array.isArray(a) === true && typeof a[0] === 'function') {
                a = a[0];

                // prepare arguments list to declare an anonymous class
                var args = [ classTemplate ],      // first of all the class has to inherit the original class
                    k    = arguments.length - 2;

                // collect interfaces the anonymous class has to implement
                for(; k >= 0 && arguments[k].clazz === Interface; k--) {
                    args.push(arguments[k]);
                }

                // add methods list
                args.push(arguments[arguments.length - 1]);

                var cl = Class.apply(null, args),  // declare new anonymous class
                    // create a function to instantiate an object that will be made the
                    // anonymous class instance. The intermediate object is required to
                    // call constructor properly since we have arguments as an array
                    f  = function() {};

                cl.$name = classTemplate.$name; // the same class name for anonymous
                f.prototype = cl.prototype; // the same prototypes

                var o = new f();

                // call constructor
                // use array copy instead of cloning with slice for performance reason
                // (Array.prototype.slice.call(arguments, 0, k + 1))
                args = [];
                for (var i = 0; i < k + 1; i++) {
                    args[i] = arguments[i];
                }
                cl.apply(o, args);

                // set constructor field for consistency
                o.constructor = cl;
                return o;
            }
        }

        // call class constructor
        if (this.$ !== undefined) { // TODO: hard-coded constructor name to speed up
            return this.$.apply(this, arguments);
        }
    }, toInherit);

    /**
     *  Internal attribute that caches properties setter references.
     *  @attribute $propertySetterInfo
     *  @type {Object}
     *  @private
     *  @for zebkit.Class
     *  @readOnly
     */

    // prepare fields that caches the class properties. existence of the property
    // force getPropertySetter method to cache the method
    classTemplate.$propertySetterInfo = {};


    classTemplate.$propertyGetterInfo = {};


    /**
     *  Reference to a parent class
     *  @attribute $parent
     *  @type {zebkit.Class}
     *  @protected
     *  @readOnly
     */

    // copy parents prototype methods and fields into
    // new class template
    classTemplate.$parent = parentClass;
    if (parentClass !== null) {
        for(var k in parentClass.prototype) {
            if (parentClass.prototype.hasOwnProperty(k)) {
                var f = parentClass.prototype[k];
                classTemplate.prototype[k] = (f !== undefined &&
                                              f !== null &&
                                              f.hasOwnProperty("methodBody")) ? $ProxyMethod(f.methodName, f.methodBody, f.boundTo)
                                                                              : f;
            }
        }
    }

    /**
     * The instance class.
     * @attribute clazz
     * @type {zebkit.Class}
     */
    classTemplate.prototype.clazz = classTemplate;

    // check if the method has been already defined in the class
    if (classTemplate.prototype.properties === undefined) {
        classTemplate.prototype.properties = function(p) {
            return properties(this, p);
        };
    }

    // populate class template prototype methods and fields
    for(var ptf in classTemplateProto) {
        classTemplate.prototype[ptf] = classTemplateProto[ptf];
    }

    // copy methods from interfaces before mixing class methods
    if (toInherit.length > 0) {
        for(var idx = toInherit[0].clazz === Interface ? 0 : 1; idx < toInherit.length; idx++) {
            var ic = toInherit[idx];
            $cpMethods(ic.prototype, classTemplate.prototype, classTemplate);

            // copy static fields from interface to the class
            for(var sk in ic) {
                if (sk[0] !== '$' &&
                    ic.hasOwnProperty(sk) === true &&
                    classTemplate.hasOwnProperty(sk) === false)
                {
                    classTemplate[sk] = clone(ic[sk]);
                }
            }
        }
    }

    // initialize uniqueness field with false
    classTemplate.$uniqueness = false;

    // inherit static fields from parent class
    if (parentClass !== null) {
        for (var key in parentClass) {
            if (key[0] !== '$' &&
                parentClass.hasOwnProperty(key) &&
                classTemplate.hasOwnProperty(key) === false)
            {
                classTemplate[key] = clone(parentClass[key]);
            }
        }

        // inherit uni
        if (parentClass.$uniqueness === true) {
            classTemplate.hashable();
        }
    }

    // add class declared methods after the previous step to get a chance to
    // overwrite class level definitions
    $mixing(classTemplate, classMethods);


    // populate class level methods and fields into class template
    for (var tf in classTemplateFields) {
        classTemplate[tf] = classTemplateFields[tf];
    }

    // assign proper name to class
    classTemplate.clazz.$name = "zebkit.Class";

    // copy methods from interfaces
    if (toInherit.length > 0) {
        // notify inherited class and interfaces that they have been inherited with the given class
        for(var j = 0; j < toInherit.length; j++) {
            if (typeof toInherit[j].inheritedWidth === 'function') {
                toInherit[j].inheritedWidth(classTemplate);
            }
        }
    }

    return classTemplate;
});

/**
 * Get class by the given class name
 * @param  {String} name a class name
 * @return {Function} a class. Throws exception if the class cannot be
 * resolved by the given class name
 * @method forName
 * @throws Error
 * @for  zebkit.Class
 */
Class.forName = function(name) {
    return $cache(name);
};


/**
 * Test if the given object is instance of the specified class or interface. It is preferable
 * to use this method instead of JavaScript "instanceof" operator whenever you are dealing with
 * zebkit classes and interfaces.
 * @param  {Object} obj an object to be evaluated
 * @param  {Function} clazz a class or interface
 * @return {Boolean} true if a passed object is instance of the given class or interface
 * @method instanceOf
 * @for  zebkit
 */
function instanceOf(obj, clazz) {
    if (clazz !== null && clazz !== undefined) {
        if (obj === null || obj === undefined)  {
            return false;
        } else if (obj.clazz === undefined) {
            return (obj instanceof clazz);
        } else {
            return obj.clazz !== null &&
                   (obj.clazz === clazz ||
                    obj.clazz.$parents[clazz.$hash$] !== undefined);
        }
    }

    throw new Error("instanceOf(): null class");
}

/**
 * Dummy class that implements nothing but can be useful to instantiate
 * anonymous classes with some on "the fly" functionality:
 *
 *     // instantiate and use zebkit class with method "a()" implemented
 *     var ac = new zebkit.Dummy([
 *          function a() {
 *             ...
 *          }
 *     ]);
 *
 *     // use it
 *     ac.a();
 *
 * @constructor
 * @class zebkit.Dummy
 */
var Dummy = Class([]);


$export(clone, instanceOf, newInstance,
        { "Class": Class, "Interface" : Interface, "Dummy": Dummy, "CDNAME": CDNAME, "CNAME" : CNAME });

/**
 * JSON object loader class is a handy way to load hierarchy of objects encoded with
 * JSON format. The class supports standard JSON types plus it extends JSON with a number of
 * features that helps to make object creation more flexible. Zson allows developers
 * to describe creation of any type of object. For instance if you have a class "ABC" with
 * properties "prop1", "prop2", "prop3" you can use instance of the class as a value of
 * a JSON property as follow:
 *
 *      { "instanceOfABC": {
 *              "@ABC"  : [],
 *              "prop1" : "property 1 value",
 *              "prop2" : true,
 *              "prop3" : 200
 *          }
 *      }
 *
 *  And than:
 *
 *       // load JSON mentioned above
 *       zebkit.Zson.then("abc.json", function(zson) {
 *           zson.get("instanceOfABC");
 *       });
 *
 *  Features the JSON zson supports are listed below:
 *
 *    - **Access to hierarchical properties** You can use dot notation to get a property value. For
 *    instance:
 *
 *     { "a" : {
 *            "b" : {
 *                "c" : 100
 *            }
 *         }
 *     }
 *
 *     zebkit.Zson.then("abc.json", function(zson) {
 *         zson.get("a.b.c"); // 100
 *     });
 *
 *
 *    - **Property reference** Every string JSON value that starts from "@" considers as reference to
 *    another property value in the given JSON.
 *
 *     {  "a" : 100,
 *        "b" : {
 *            "c" : "%{a.b}"
 *        }
 *     }
 *
 *    here property "b.c" equals to 100 since it refers to  property "a.b"
 *     *
 *    - **Class instantiation**  Property can be easily initialized with an instantiation of required class. JSON
 *    zson considers all properties whose name starts from "@" character as a class name that has to be instantiated:
 *
 *     {  "date": {
 *           { "@Date" : [] }
 *         }
 *     }
 *
 *   Here property "date" is set to instance of JS Date class.
 *
 *   - **Factory classes** JSON zson follows special pattern to describe special type of property whose value
 *   is re-instantiated every time the property is requested. Definition of the property value is the same
 *   to class instantiation, but the name of class has to prefixed with "*" character:
 *
 *
 *     {  "date" : {
 *           "@ *Date" : []
 *        }
 *     }
 *
 *
 *   Here, every time you call get("date") method a new instance of JS date object will be returned. So
 *   every time will have current time.
 *
 *   - **JS Object initialization** If you have an object in your code you can easily fulfill properties of the
 *   object with JSON zson. For instance you can create zebkit UI panel and adjust its background, border and so on
 *   with what is stored in JSON:
 *
 *
 *     {
 *       "background": "red",
 *       "borderLayout": 0,
 *       "border"    : { "@zebkit.draw.RoundBorder": [ "black", 2 ] }
 *     }
 *
 *     var pan = new zebkit.ui.Panel();
 *     new zebkit.Zson(pan).then("pan.json", function(zson) {
 *         // loaded and fulfill panel
 *         ...
 *     });
 *
 *
 *   - **Expression** You can evaluate expression as a property value:
 *
 *
 *     {
 *         "a": { ".expr":  "100*10" }
 *     }
 *
 *
 *   Here property "a" equals 1000
 *
 *
 *   - **Load external resources** You can combine Zson from another Zson:
 *
 *
 *     {
 *         "a": "%{<json> embedded.json}",
 *         "b": 100
 *     }
 *
 *
 *   Here property "a" is loaded with properties set with loading external "embedded.json" file
 *
 * @class zebkit.Zson
 * @constructor
 * @param {Object} [obj] a root object to be loaded with
 * the given JSON configuration
 */
var Zson = Class([
    function (root) {
        if (arguments.length > 0) {
            this.root = root;
        }

        /**
         * Map of aliases and appropriate classes
         * @attribute classAliases
         * @protected
         * @type {Object}
         * @default {}
         */
        this.classAliases = {};
    },

    function $clazz() {
        /**
         * Build zson from the given json file
         * @param  {String|Object}   json a JSON or path to JSOn file
         * @param  {Object}   [root] an object to be filled with the given JSON
         * @param  {Function} [cb]   a callback function to catch the JSON loading is
         * completed
         * @return {zebkit.DoIt} a promise to catch result
         * @method  then
         * @static
         */
        this.then = function(json, root, cb) {
            if (typeof root === 'function') {
                cb   = root;
                root = null;
            }

            var zson = arguments.length > 1 && root !== null ? new Zson(root)
                                                             : new Zson();

            if (typeof cb === 'function') {
                return zson.then(json, cb);
            } else {
                return zson.then(json);
            }
        };
    },

    function $prototype() {
        /**
         * URL the JSON has been loaded from
         * @attribute  uri
         * @type {zebkit.URI}
         * @default null
         */
        this.uri = null;

        /**
         * Object that keeps loaded and resolved content of a JSON
         * @readOnly
         * @attribute root
         * @type {Object}
         * @default {}
         */
        this.root = null;

        /**
         * Original JSON as a JS object
         * @attribute content
         * @protected
         * @type {Object}
         * @default null
         */
        this.content = null;

        /**
         * The property says if the object introspection is required to try find a setter
         * method for the given key. For instance if an object is loaded with the
         * following JSON:

         {
            "color": "red"
         }

         * the introspection will cause zson class to try finding "setColor(c)" method in
         * the loaded with the JSON object and call it to set "red" property value.
         * @attribute usePropertySetters
         * @default true
         * @type {Boolean}
         */
        this.usePropertySetters = true;

        /**
         * Cache busting flag.
         * @attribute cacheBusting
         * @type {Boolean}
         * @default false
         */
        this.cacheBusting = false;

        /**
         * Internal variables set
         * @attribute $variables
         * @protected
         * @type {Object}
         */
        this.$variables = null;

        /**
         * Base URI to be used to build paths to external resources. The path is
         * used for references that occur in zson.
         * @type {String}
         * @attribute baseUri
         * @default null
         */
        this.baseUri = null;

        /**
         * Get a property value by the given key. The property name can point to embedded fields:
         *
         *      new zebkit.Zson().then("my.json", function(zson) {
         *          zson.get("a.b.c");
         *      });
         *
         *
         * @param  {String} key a property key.
         * @return {Object} a property value
         * @throws Error if property cannot be found and it  doesn't start with "?"
         * @method  get
         */
        this.get = function(key) {
            if (key === null || key === undefined) {
                throw new Error("Null key");
            }

            var ignore = false;
            if (key[0] === '?') {
                key = key.substring(1).trim();
                ignore = true;
            }

            if (ignore) {
                try {
                    return getPropertyValue(this.root, key);
                } catch(e) {
                    if ((e instanceof ReferenceError) === false) {
                        throw e;
                    }
                }
            } else {
                return getPropertyValue(this.root, key);
            }
        };

        /**
         * Call the given method defined with the Zson class instance and
         * pass the given arguments to the method.
         * @param  {String} name a method name
         * @param  {Object} d arguments
         * @return {Object} a method execution result
         * @method callMethod
         */
        this.callMethod = function(name, d) {
            var m  = this[name.substring(1).trim()],
                ts = this.$runner.$tasks.length,
                bs = this.$runner.$busy;

            if (typeof m !== 'function') {
                throw new Error("Method '" + name + "' cannot be found");
            }

            var args = this.buildValue(Array.isArray(d) ? d
                                                        : [ d ]),
                $this = this;

            if (this.$runner.$tasks.length === ts &&
                this.$runner.$busy === bs           )
            {
                var res = m.apply(this, args);
                if (res instanceof DoIt) {
                    return new DoIt().till(this.$runner).then(function() {
                        var jn = this.join();
                        res.then(function(res) {
                            jn(res);
                            return res;
                        }).then(function(res) {
                            return res;
                        });
                    }).catch(function(e) {
                        $this.$runner.error(e);
                    });
                } else {
                    return res;
                }
            } else {
                return new DoIt().till(this.$runner).then(function() {
                    if (args instanceof DoIt) {
                        var jn = this.join();
                        args.then(function(res) {
                            jn(res);
                            return res;
                        });
                    } else {
                        return args;
                    }
                }).then(function(args) {
                    var res = m.apply($this, args);
                    if (res instanceof DoIt) {
                        var jn = this.join();
                        res.then(function(res) {
                            jn(res);
                            return res;
                        });
                    } else {
                        return res;
                    }
                }).then(function(res) {
                    return res;
                }).catch(function(e) {
                    $this.$runner.error(e);
                });
            }
        };

        /**
         * Resolve the given reference
         * @param  {Object} target a target object
         * @param  {Array} names a reference names
         * @return {Object | zebkit.DoIt} a resolved by the reference value of promise if
         * the object cannot be resolved immediately
         * @private
         * @method $resolveRef
         */
        this.$resolveRef = function(target, names) {
            var fn = function(ref, rn) {
                rn.then(function(target) {
                    if (target !== null && target !== undefined && target.hasOwnProperty(ref) === true) {
                        var v = target[ref];
                        if (v instanceof DoIt) {
                            var jn = this.join();
                            v.then(function(res) {
                                jn.call(rn, res);
                                return res;
                            });
                        } else {
                            return v;
                        }
                    } else {
                        return undefined;
                    }
                });
            };

            for (var j = 0; j < names.length; j++) {
                var ref = names[j];

                if (target.hasOwnProperty(ref)) {
                    var v = target[ref];

                    if (v instanceof DoIt) {
                        var rn      = new DoIt(),
                            trigger = rn.join();

                        for(var k = j; k < names.length; k++) {
                            fn(names[k], rn);
                        }

                        trigger.call(rn, target);
                        return rn;
                    } else {
                        target = target[ref];
                    }

                } else {
                    return undefined;
                }
            }

            return target;
        };

        /**
         * Build the given array. Building means all references have to be resolved.
         * @param  {Array} d an array to be resolved.
         * @return {Array|zebkit.DoIt} a resolved object of promise if the array cannot be resolved immediately
         * @private
         * @method $buildArray
         */
        this.$buildArray = function(d) {
            var hasAsync = false;
            for (var i = 0; i < d.length; i++) {
                var v = this.buildValue(d[i]);
                if (v instanceof DoIt) {
                    hasAsync = true;
                    this.$assignValue(d, i, v);
                } else {
                    d[i] = v;
                }
            }

            if (hasAsync) {
                return new DoIt().till(this.$runner).then(function() {
                    return d;
                });
            } else {
                return d;
            }
        };

        /**
         * Build a class instance.
         * @param  {String} classname a class name
         * @param  {Array|null|Object} args  a class constructor arguments
         * @param  {Object} props properties to be applied to class instance
         * @return {Object|zebkit.DoIt}
         * @method $buildClass
         * @private
         */
        this.$buildClass = function(classname, args, props) {
            var clz       = null,
                busy      = this.$runner.$busy,
                tasks     = this.$runner.$tasks.length;

            classname = classname.trim();

            // '?' means optional class instance.
            if (classname[0] === '?') {
                classname = classname.substring(1).trim();
                try {
                    clz = this.resolveClass(classname[0] === '*' ? classname.substring(1).trim()
                                                                 : classname);
                } catch (e) {
                    return null;
                }
            } else {
                clz = this.resolveClass(classname[0] === '*' ? classname.substring(1).trim()
                                                             : classname);
            }

            args = this.buildValue(Array.isArray(args) ? args
                                                       : [ args ]);

            if (classname[0] === '*') {
                return (function(clazz, args) {
                    return {
                        $new : function() {
                            return newInstance(clazz, args);
                        }
                    };
                })(clz, args);
            }

            var props = this.buildValue(props);

            // let's do optimization to avoid unnecessary overhead
            // equality means nor arguments neither properties has got async call
            if (this.$runner.$busy === busy && this.$runner.$tasks.length === tasks) {
                var inst = newInstance(clz, args);
                this.merge(inst, props, true);
                return inst;
            } else {
                var $this = this;
                return new DoIt().till(this.$runner).then(function() {
                    var jn1 = this.join(),  // create all join here to avoid result overwriting
                        jn2 = this.join();

                    if (args instanceof DoIt) {
                        args.then(function(res) {
                            jn1(res);
                            return res;
                        });
                    } else {
                        jn1(args);
                    }

                    if (props instanceof DoIt) {
                        props.then(function(res) {
                            jn2(res);
                            return res;
                        });
                    } else {
                        jn2(props);
                    }
                }).then(function(args, props) {
                    var inst = newInstance(clz, args);
                    $this.merge(inst, props, true);
                    return inst;
                });
            }
        };

        /**
         * Map query string parameters to dictionary of variables.
         * @param  {String|zebkitURI} uri an URI.
         * @return {Object} a set of variables fetched from the query string of the given URI.
         * @method $qsToVars
         * @private
         */
        this.$qsToVars = function(uri) {
            var qs   = null,
                vars = null;

            if ((uri instanceof URI) === false) {
                qs = new URI(uri.toString()).qs;
            } else {
                qs = uri.qs;
            }

            if (qs !== null || qs === undefined) {
                qs = URI.parseQS(qs);
                for(var k in qs) {
                    if (vars === null) {
                        vars = {};
                    }
                    vars[k] = URI.decodeQSValue(qs[k]);
                }
            }

            return vars;
        };

        /**
         * Resolve the given reference.
         * @param  {String} d a reference.
         * @return {Object|zebkit.DoIt} a resolved reference value or promise if it cannot be resolved immediately.
         * @method $buildRef
         */
        this.$buildRef = function(d) {
            var idx = -1;

            if (d[2] === "<" || d[2] === '.' || d[2] === '/') { //TODO: not complete solution that cannot detect URLs
                var path  = null,
                    type  = null,
                    $this = this;

                if (d[2] === '<') {
                    // if the referenced path is not absolute path and the zson has been also
                    // loaded by an URL than build the full URL as a relative path from
                    // BAG URL
                    idx = d.indexOf('>');
                    if (idx <= 4) {
                        throw new Error("Invalid content type in URL '" + d + "'");
                    }

                    path = d.substring(idx + 1, d.length - 1).trim();
                    type = d.substring(3, idx).trim();
                } else {
                    path = d.substring(2, d.length - 1).trim();
                    type = "json";
                }

                if (type === 'js') {
                    return this.expr(path);
                }

                if (URI.isAbsolute(path) === false) {
                    if (this.baseUri !== null) {
                        path = URI.join(this.baseUri, path);
                    } else if (this.uri !== null) {
                        var pURL = new URI(this.uri).getParent();
                        if (pURL !== null) {
                            path = URI.join(pURL, path);
                        }
                    }
                }

                if (type === "json") {
                    var bag = new this.clazz();
                    bag.usePropertySetters = this.usePropertySetters;
                    bag.$variables         = this.$qsToVars(path);
                    bag.cacheBusting       = this.cacheBusting;

                    var bg = bag.then(path).catch();
                    this.$runner.then(bg.then(function(res) {
                        return res.root;
                    }));
                    return bg;
                } else if (type === 'img') {
                    if (this.uri !== null && URI.isAbsolute(path) === false) {
                        path = URI.join(new URI(this.uri).getParent(), path);
                    }
                    return image(path, false);
                } else if (type === 'txt') {
                    return new ZFS.GET(path).then(function(r) {
                        return r.responseText;
                    }).catch(function(e) {
                        $this.$runner.error(e);
                    });
                } else {
                    throw new Error("Invalid content type " + type);
                }

            } else {
                // ? means don't throw exception if reference cannot be resolved
                idx = 2;
                if (d[2] === '?') {
                    idx++;
                }

                var name = d.substring(idx, d.length - 1).trim(),
                    names   = name.split('.'),
                    targets = [ this.$variables, this.content, this.root, $global];

                for(var i = 0; i < targets.length; i++) {
                    var target = targets[i];
                    if (target !== null) {
                        var value = this.$resolveRef(target, names);
                        if (value !== undefined) {
                            return value;
                        }
                    }
                }

                if (idx === 2) {
                    throw new Error("Reference '" + name + "' cannot be resolved");
                } else {
                    return d;
                }
            }
        };

        /**
         * Build a value by the given JSON description
         * @param  {Object} d a JSON description
         * @return {Object} a value
         * @protected
         * @method buildValue
         */
        this.buildValue = function(d) {
            if (d === undefined || d === null || d instanceof DoIt ||
                (typeof d === "number"   || d.constructor === Number)  ||
                (typeof d === "boolean"  || d.constructor === Boolean)    )
            {
                return d;
            }

            if (Array.isArray(d)) {
                return this.$buildArray(d);
            }

            if (typeof d === "string" || d.constructor === String) {
                if (d[0] === '%' && d[1] === '{' && d[d.length - 1] === '}') {
                    return this.$buildRef(d);
                } else {
                    return d;
                }
            }

            var k = null;

            if (d.hasOwnProperty("class") === true) {
                k = d["class"];
                delete d["class"];

                if (isString(k) === false) {
                    var kk = null;
                    for (kk in k) {
                        return this.$buildClass(kk, k[kk], d);
                    }
                }
                return this.$buildClass(k, [], d);
            }

            // test whether we have a class definition
            for (k in d) {
                // handle class definition
                if (k[0] === '@' && d.hasOwnProperty(k) === true) {
                    var args = d[k];
                    delete d[k]; // delete class name
                    return this.$buildClass(k.substring(1), args, d);
                }

                //!!!!  trust the name of class occurs first what in general
                //      cannot be guaranteed by JSON spec but we can trust
                //      since many other third party applications stands
                //      on it too :)
                break;
            }

            for (k in d) {
                if (d.hasOwnProperty(k)) {
                    var v = d[k];

                    // special field name that says to call method to create a
                    // value by the given description
                    if (k[0] === "." || k[0] === '#') {
                        delete d[k];
                        if (k[0] === '#') {
                            this.callMethod(k, v);
                        } else {
                            return this.callMethod(k, v);
                        }
                    } else if (k[0] === '%') {
                        delete d[k];
                        this.mixin(d, this.$buildRef(k));
                    } else {
                        this.$assignValue(d, k, this.buildValue(v));
                    }
                }
            }

            return d;
        };

        this.$assignValue = function(o, k, v) {
            o[k] = v;
            if (v instanceof DoIt) {
                this.$runner.then(v.then(function(res) {
                    o[k] = res;
                    return res;
                }));
            }
        };

        this.$assignProperty = function(o, m, v) {
            // setter has to be placed in queue to let
            // value resolves its DoIts
            this.$runner.then(function(res) {
                if (Array.isArray(v)) {
                    m.apply(o, v);
                } else {
                    m.call (o, v);
                }
                return res;
            });
        };

        /**
         * Merge values of the given destination object with the values of
         * the specified  source object.
         * @param  {Object} dest  a destination object
         * @param  {Object} src   a source object
         * @param  {Boolean} [recursively] flag that indicates if the complex
         * properties of destination object has to be traversing recursively.
         * By default the flag is true. The destination property value is
         * considered not traversable if its class defines "mergeable" property
         * that is set top true.
         * @return {Object} a merged destination object.
         * @protected
         * @method merge
         */
        this.merge = function(dest, src, recursively) {
            if (arguments.length < 3) {
                recursively = true;
            }

            for (var k in src) {
                if (src.hasOwnProperty(k)) {
                    var sv = src [k],
                        dv = dest[k];

                    if (this.usePropertySetters === true) {
                        var m = getPropertySetter(dest, k);
                        if (m !== null) {
                            this.$assignProperty(dest, m, sv);
                            continue;
                        }
                    }

                    if (isAtomic(dv) || Array.isArray(dv) ||
                        isAtomic(sv) || Array.isArray(sv) ||
                        sv.clazz !== undefined              )
                    {
                        this.$assignValue(dest, k, sv);
                    } else if (recursively === true) {
                        if (dv !== null && dv !== undefined && dv.clazz !== undefined && dv.clazz.mergeable === false) {
                            this.$assignValue(dest, k, sv);
                        } else {
                            this.merge(dv, sv);
                        }
                    }
                }
            }
            return dest;
        };

        /**
         * One level mixing of values of the destination object with the source object values.
         * @param  {Object} dest a destination object
         * @param  {Object} src  a source object
         * @method mixin
         * @protected
         */
        this.mixin = function(dest, src) {
            if (src instanceof DoIt) {
                var $this = this;
                this.$runner.then(src.then(function(src) {
                    for (var k in src) {
                        if (src.hasOwnProperty(k) && (dest[k] === undefined || dest[k] === null)) {
                            $this.$assignValue(dest, k, src[k]);
                        }
                    }
                }));
            } else {
                for (var k in src) {
                    if (src.hasOwnProperty(k) && (dest[k] === undefined || dest[k] === null)) {
                        this.$assignValue(dest, k, src[k]);
                    }
                }
            }
        };

        /**
         * Called every time the given class name has to be transformed into
         * the class object (constructor) reference. The method checks if the given class name
         * is alias that is mapped with the zson to a class.
         * @param  {String} className a class name
         * @return {Function} a class reference
         * @method resolveClass
         * @protected
         */
        this.resolveClass = function(className) {
            return this.classAliases.hasOwnProperty(className) ? this.classAliases[className]
                                                               : Class.forName(className);
        };

        /**
         * Adds class aliases
         * @param {Object} aliases dictionary where key is a class alias that can be referenced
         * from JSON and the value is class itself (constructor)
         * @method  addClassAliases
         */
        this.addClassAliases = function(aliases) {
            for(var k in aliases) {
                this.classAliases[k] = Class.forName(aliases[k].trim());
            }
        };

        /**
         * Evaluate the given expression
         * @param  {String} expr an expression.
         * @return {Object} a result of the expression evaluation
         * @method expr
         */
        this.expr = function(expr) {
            if (expr.length > 300) {
                throw new Error("Out of evaluated script limit");
            }

            return eval("'use strict';" + expr);
        };

        /**
         * Load and parse the given JSON content.
         * @param  {String|Object} json a JSON content. It can be:
         *    - **String**
         *       - JSON string
         *       - URL to a JSON
         *    - **Object** JavaScript object
         * @return {zebkit.DoIt} a reference to the runner
         * @method then
         * @example
         *
         *     // load JSON in zson from a remote site asynchronously
         *     new zebkit.Zson().then("http://test.com/test.json", function(zson) {
         *             // zson is loaded and ready for use
         *             zson.get("a.c");
         *         }
         *     ).catch(function(error) {
         *         // handle error
         *         ...
         *     });
         */
        this.then = function(json, fn) {
            if (json === null || json === undefined || (isString(json) && json.trim().length === 0)) {
                throw new Error("Null content");
            }

            this.$runner = new DoIt();

            var $this = this;
            this.$runner.then(function() {
                if (isString(json)) {
                    json = json.trim();

                    // detect if the passed string is not a JSON, but URL
                    if ((json[0] !== '[' || json[json.length - 1] !== ']') &&
                        (json[0] !== '{' || json[json.length - 1] !== '}')   )
                    {
                        $this.$variables = $this.$qsToVars(json);

                        $this.uri = json;

                        if ($this.cacheBusting === false) {
                            $this.uri = $this.uri + (json.lastIndexOf("?") > 0 ? "&" : "?") + (new Date()).getTime().toString();
                        }

                        var join = this.join();
                        ZFS.GET($this.uri).then(function(r) {
                            join.call($this, r.responseText);
                        }).catch(function(e) {
                            $this.$runner.error(e);
                        });
                    } else {
                        return json;
                    }
                } else {
                    return json;
                }
            }).then(function(json) { // populate JSON content
                if (isString(json)) {
                    try {
                        if ($this.uri !== null && typeof jsyaml !== 'undefined') {
                            var uri = new URI($this.uri);
                            if (uri.path !== null && uri.path.toLowerCase().indexOf(".yaml") === uri.path.length - 5) {
                                $this.content = jsyaml.load(json.trim());
                            }
                        }

                        if ($this.content === null) {
                            $this.content = $zenv.parseJSON(json.trim());
                        }
                    } catch(e) {
                        throw new Error("JSON format error: " + e);
                    }
                } else {
                    $this.content = json;
                }

                $this.$assignValue($this, "content", $this.buildValue($this.content));
            }).then(function() {
                if ($this.root !== null) {
                    $this.merge($this.root, $this.content);
                } else {
                    $this.root = $this.content;
                }

                return $this;
            });

            if (typeof $this.completed === 'function') {
                this.$runner.then(function() {
                    $this.completed.call($this);
                    return $this;
                });
            }

            if (arguments.length > 1) {
                this.$runner.then(fn);
            }

            return this.$runner;
        };
    }
]);

$export({ "Zson" : Zson } );
/**
 *  Finds an item by xpath-like simplified expression applied to a tree-like structure.
 *  Passed tree-like structure doesn't have a special requirements except every item of
 *  the structure have to define its kids by exposing "kids" field. The field is array
 *  of children elements:
 *
 *      // example of tree-like structure
 *      var treeLikeRoot = {
 *          value : "Root",
 *          kids : [
 *              { value: "Item 1" },
 *              { value: "Item 2" }
 *          ]
 *      };
 *
 *      zebkit.findInTree(treeLikeRoot,
 *          "/item1",
 *          function(foundElement) {
 *             ...
 *             // returning true means stop lookup
 *             return true;
 *          },
 *          function(item, fragment) {
 *              return item.value === fragment;
 *          });
 *
 *
 * The find method traverse the tree-like structure according to the xpath-like
 * expression. To understand if the given tree item confronts with the currently
 * traversing path fragment a special equality method has to be passed. The method
 * gets the traversing tree item and a string path fragment. The method has to
 * decide if the given tree item complies the specified path fragment.
 *
 * @param  {Object} root a tree root element. If the element has a children elements
 * the children have to be stored in "kids" field as an array.
 * @param  {String}  path a path-like expression. The path has to satisfy number of
 * requirements:
 *
 *   - has to start with "." or "/" or "//" character
 *   - has to define path part after "/" or "//"
 *   - path part can be either "*" or a name
 *   - the last path that starts from '@' character is considered as an attribute
 *     value requester In this case an attribute value will be returned.
 *   - optionally an attribute or/and its value can be defined as "[@<attr_name>=<attr_value>]"
 *   - attribute value is optional and can be boolean (true or false), integer, null
 *     or string value
 *   - string attribute value has to be wrapped with single quotes
 *
 *
 * For examples:
 *
 *   - "//*" traverse all tree elements
 *   - "//*[@a=10]" traverse all tree elements that has an attribute "a" that equals 10
 *   - "//*[@a]" traverse all tree elements that has an attribute "a" defined
 *   - "/Item1/Item2" find an element by exact path
 *   - ".//" traverse all tree elements including the root element
 *   - "./Item1/@k" value of property 'k' for a tree node found with "./Item1" path
 *
 * @param  {Function} cb callback function that is called every time a new tree element
 * matches the given path fragment. The function has to return true if the tree look up
 * has to be interrupted
 * @param  {Function}  [eq]  an equality function. The function gets current evaluated
 * tree element and a path fragment against which the tree element has to be evaluated.
 * It is expected the method returns boolean value to say if the given passed tree
 * element matches the path fragment. If the parameter is not passed or null then default
 * equality method is used. The default method expects a tree item has "path" field that
 * is matched with  given path fragment.
 * @method findInTree
 * @for  zebkit
 */

var PATH_RE = /^[.]?(\/[\/]?)([^\[\/]+)(\[\s*\@([a-zA-Z_][a-zA-Z0-9_\.]*)\s*(\=\s*[0-9]+|\=\s*true|\=\s*false|\=\s*null|\=\s*\'[^']*\')?\s*\])?/,
    DEF_EQ  =  function(n, fragment) { return n.value === fragment; };

function findInTree(root, path, cb, eq) {
    if (root === null || root === undefined) {
        throw new Error("Null tree root");
    }

    path = path.trim();
    if (path[0] === '#') {  // id shortcut
        path = "//*[@id='" + path.substring(1).trim() + "']";
    } else if (path === '.') { // current node shortcut
        return cb.call(root, root);
    } else if (path[0] === '.' && path[1] === '/') { // means we have to include root in search
        if (path[2] !== '@') {
            root = { kids: [ root ] };
        }
        path = path.substring(1);
    }

    // no match method has been defined, let use default method
    // to match the given node to the current path fragment
    if (eq === null || arguments.length < 4) {  // check null first for perf.
        eq = DEF_EQ;
    }

    return $findInTree(root, path, cb, eq, null);
}

function $findInTree(root, path, cb, eq, m) {
    if (path[0] === '/' && path[1] === '/' && path[2] === '@') {
        path = "//*" + path.substring(1);
    }

    var pathValue,
        pv         = undefined,
        isTerminal = false;

    if (path[0] === '/' && path[1] === '@') {
        if (m === null || m[0].length !== m.input.length) {
            m = path.match(PATH_RE);

            if (m === null) {
                throw new Error("Cannot resolve path '" + path + "'");
            }

            // check if the matched path is not terminal
            if (m[0].length !== path.length) {
                path = path.substring(m[0].length);  // cut found fragment from the path
            }
        }

        pathValue = m[2].trim();
        if (pathValue[1] === '{') {
            if (pathValue[pathValue.length - 1] !== '}') {
                throw new Error("Invalid properties aggregation expression '" + pathValue + "'");
            }

            pv = {};
            var names = pathValue.substring(2, pathValue.length - 1).split(',');
            for (var ni = 0; ni < names.length; ni++) {
                var name = names[ni].trim();
                pv[name] = getPropertyValue(root, name, true);
            }
        } else {
            pv = getPropertyValue(root, pathValue.substring(1), true);
        }

        if (m[0].length === m.input.length) {  // terminal path
            if (pv !== undefined && cb.call(root, pv) === true) {
                return true;
            }
        } else {
            if (isAtomic(pv)) {
                throw new Error("Atomic typed node cannot be traversed");
            } else if (pv !== null && pv !== undefined) {
                if ($findInTree(pv, path, cb, eq, m) === true) {
                    return true;
                }
            }
        }
    } else if (root.kids !== undefined &&   // a node has children
               root.kids !== null      &&
               root.kids.length > 0       ) {

        var ppath = path;
        //
        // m == null                      : means this is the first call of the method
        // m[0].length !== m.input.length : means this is terminal part of the path
        //
        if (m === null || m[0].length !== m.input.length) {
            m = path.match(PATH_RE);

            if (m === null) {
                throw new Error("Cannot resolve path '" + path + "'");
            }

            // check if the matched path is not terminal
            if (m[0].length !== path.length) {
                path = path.substring(m[0].length);  // cut found fragment from the path
            }

            // normalize attribute value
            if (m[3] !== undefined && m[5] !== undefined) {
                m[5] = m[5].substring(1).trim();

                if (m[5][0] === "'") {
                    m[5] = m[5].substring(1, m[5].length - 1);
                } else if (m[5] === "true") {
                    m[5] = true;
                } else if (m[5] === "false") {
                    m[5] = false;
                } else if (m[5] === "null") {
                    m[5] = null;
                } else {
                    var vv = parseInt(m[5], 10);
                    if (isNaN(vv) === false) {
                        m[5] = vv;
                    }
                }
            }
        }

        if (m[0].length === m.input.length) {
            isTerminal = true;
        }
        pathValue = m[2].trim();

        // traverse root kid nodes
        for (var i = 0; i < root.kids.length ; i++) {
            var kid     = root.kids[i],
                isMatch = false;
                                        // XOR
            if (pathValue === "*" || (eq(kid, pathValue) ? pathValue[0] !== '!' : pathValue[0] === '!') === true) {
                if (m[3] !== undefined) { // has attributes
                    var attrName = m[4].trim();

                    // leave if attribute doesn't match
                    if (kid[attrName] !== undefined && (m[5] === undefined || kid[attrName] === m[5])) {
                        isMatch = true;
                    }
                } else {
                    isMatch = true;
                }
            }

            if (isTerminal === true) {
                // node match then call callback and leave if the callback says to do it
                if (isMatch === true) {
                    if (cb.call(root, kid) === true) {
                        return true;
                    }
                }

                if (m[1] === "//") {
                    if ($findInTree(kid, path, cb, eq, m) === true) {
                       return true;
                    }
                }
            } else {
                // not a terminal and match, then traverse kid
                if (isMatch === true) {
                    if ($findInTree(kid, path, cb, eq, m) === true) {
                        return true;
                    }
                }

                // not a terminal and recursive traversing then do it
                // with previous path
                if (m[1] === "//") {
                    if ($findInTree(kid, ppath, cb, eq, m) === true) {
                        return true;
                    }
                }
            }
        }
    }

    return false;
}

/**
 * Interface that provides path search functionality for a tree-like structure.
 * @class  zebkit.PathSearch
 * @interface zebkit.PathSearch
 */
var PathSearch = Interface([
    function $prototype() {
        /**
         *  Method to match two element in tree.
         *  @protected
         *  @attribute $matchPath
         *  @type {Function}
         */
         this.$matchPath = null;

        /**
         * Find children items or values with the passed path expression.
         * @param  {String} path path expression. Path expression is simplified form
         * of XPath-like expression. See  {{#crossLink "findInTree"}}findInTree{{/crossLink}}
         * method to get more details.
         *
         * @param {Function} [cb] function that is called every time a new children
         * component has been found. If callback has not been passed then the method
         * return first found item or null. If the callback has been passed as null
         * then all found elements will be returned as array.
         * @method byPath
         * @return {Object} found children item/property value or null if no children
         * items were found
         */
        this.byPath = function(path, cb) {
            if (arguments.length === 2) {
                if (arguments[1] === null) {
                    var r = [];
                    findInTree(this, path, function(n) {
                        r.push(n);
                        return false;
                    }, this.$matchPath !== null ? this.$matchPath
                                                : null);
                    return r;
                } else {
                    findInTree(this, path, cb, this.$matchPath !== null ? this.$matchPath
                                                                        : null);
                }
            } else {
                var res = null;
                findInTree(this, path, function(n) {
                    res = n;
                    return true;
                }, this.$matchPath !== null ? this.$matchPath : null);
                return res;
            }
        };
    }
]);

$export(findInTree, { "PathSearch": PathSearch } );
/**
 * Abstract event class.
 * @class zebkit.Event
 * @constructor
 */
var Event = Class([
    function $prototype() {
        /**
         * Source of an event
         * @attribute source
         * @type {Object}
         * @default null
         * @readOnly
         */
        this.source = null;
    }
]);

/**
 * This method allows to declare a listeners container class for the given
 * dedicated event types.
 *
 *     // create listener container to keep three different events
 *     // handlers
 *     var MyListenerContainerClass = zebkit.ListenersClass("event1",
 *                                                          "event2",
 *                                                          "event3");
 *     // instantiate listener class container
 *     var listeners = new MyListenerContainerClass();
 *
 *     // add "event1" listener
 *     listeners.add(function event1() {
 *         ...
 *     });
 *
 *     // add "event2" listener
 *     listeners.add(function event2() {
 *        ...
 *     });
 *
 *     // add listener for both event1 and event2 events
 *     listeners.add(function() {
 *        ...
 *     });
 *
 *     // and firing event1 to registered handlers
 *     listeners.event1(...);
 *
 *     // and firing event2 to registered handlers
 *     listeners.event2(...);
 *
 * @for zebkit
 * @method ListenersClass
 * @param {String} [events]* events types the listeners container has to support
 * @return {zebkit.Listener} a listener container class
 */
var $NewListener = function() {
    var clazz = function() {};
    clazz.eventNames = arguments.length === 0 ? [ "fired" ]
                                              : Array.prototype.slice.call(arguments);

    clazz.ListenersClass = function() {
        var args = this.eventNames.slice(); // clone
        for(var i = 0; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        return $NewListener.apply(this, args);
    };

    if (clazz.eventNames.length === 1) {
        var $ename = clazz.eventNames[0];

        clazz.prototype.v = null;

        clazz.prototype.add = function() {
            var ctx = this,
                l   = arguments[arguments.length - 1]; // last arguments are handler(s)

            if (typeof l !== 'function') {
                ctx = l;
                l   = l[$ename];

                if (typeof l !== "function") {
                    return null;
                }
            }

            if (arguments.length > 1 && arguments[0] !== $ename) {
                throw new Error("Unknown event type :" + $ename);
            }

            if (this.v === null) {
                this.v = [];
            }

            this.v.push(ctx, l);
            return l;
        };

        clazz.prototype.remove = function(l) {
            if (this.v !== null) {
                if (arguments.length === 0) {
                    // remove all
                    this.v.length = 0;
                } else {
                    var name = arguments.length > 1 || zebkit.isString(arguments[0]) ? arguments[0]
                                                                                     : null,
                        fn   = arguments.length > 1 ? arguments[1]
                                                    : (name === null ? arguments[0] : null),
                        i    = 0;

                    if (name !== null && name !== $ename) {
                        throw new Error("Unknown event type :" + name);
                    }

                    if (fn === null) {
                        this.v.length = 0;
                    } else {
                        while ((i = this.v.indexOf(fn)) >= 0) {
                            if (i % 2 > 0) {
                                i--;
                            }
                            this.v.splice(i, 2);
                        }
                    }
                }
            }
        };

        clazz.prototype.hasHandler = function(l) {
            if (zebkit.isString(l)) {
                return this.v !== null && l === $ename && this.v.length > 0;
            } else {
                return this.v.length > 0 && this.v.indexOf(l) >= 0;
            }
        };

        clazz.prototype[$ename] = function() {
            if (this.v !== null) {
                for (var i = 0; i < this.v.length; i += 2) {
                    if (this.v[i + 1].apply(this.v[i], arguments) === true) {
                        return true;
                    }
                }
            }
            return false;
        };

        clazz.prototype.hasEvent = function(nm) {
            return nm === $ename;
        };
    } else {
        var names = {};
        for(var i = 0; i < clazz.eventNames.length; i++) {
            names[clazz.eventNames[i]] = true;
        }

        clazz.prototype.$methods = null;

        clazz.prototype.add = function(l) {
            if (this.$methods === null) {
                this.$methods = {};
            }

            var n   = null,
                k   = null,
                nms = this.$names !== undefined ? this.$names : names;

            if (arguments.length > 1) {
                n = arguments[0];
                l = arguments[arguments.length - 1]; // last arguments are handler(s)
            }

            if (typeof l === 'function') {
                if (n !== null && nms[n] === undefined) {
                    throw new Error("Unknown event type " + n);
                }

                if (n === null) {
                    for(k in nms) {
                        if (this.$methods[k] === undefined) {
                            this.$methods[k] = [];
                        }
                        this.$methods[k].push(this, l);
                    }
                } else {
                    if (this.$methods[n] === undefined) {
                        this.$methods[n] = [];
                    }
                    this.$methods[n].push(this, l);
                }
            } else {
                var b = false;
                for (k in nms) {
                    if (typeof l[k] === "function") {
                        b = true;
                        if (this.$methods[k] === undefined) {
                            this.$methods[k] = [];
                        }
                        this.$methods[k].push(l, l[k]);
                    }
                }

                if (b === false) {
                    return null;
                }
            }
            return l;
        };

        clazz.prototype.hasHandler = function(l) {
            if (zebkit.isString(l)) {
                return this.$methods !== null &&
                       this.$methods.hasOwnProperty(l) &&
                       this.$methods[l].length > 0;
            } else {
                for(var k in this.$methods) {
                    var v = this.$methods[k];
                    if (v.indexOf(l) >= 0) {
                        return true;
                    }
                }
                return false;
            }
        };

        clazz.prototype.addEvents = function() {
            if (this.$names === undefined) {
                this.$names = {};
                for (var k in names) {
                    this.$names[k] = names[k];
                }
            }

            for(var i = 0; i < arguments.length; i++) {
                var name = arguments[i];

                if (name === null || name === undefined || this[name] !== undefined) {
                    throw new Error("Invalid " + name + " (event name)");
                }

                this[name] = (function(name) {
                    return function() {
                        // typeof is faster then hasOwnProperty under nodejs
                        if (this.$methods !== null && this.$methods[name] !== undefined) {
                            var c = this.$methods[name];
                            for(var i = 0; i < c.length; i += 2) {
                                if (c[i + 1].apply(c[i], arguments) === true) {
                                    return true;
                                }
                            }
                        }
                        return false;
                    };
                })(name);

                this.$names[name] = true;
            }
        };

        // populate methods that has to be called to send appropriate events to
        // registered listeners
        clazz.prototype.addEvents.apply(clazz.prototype, clazz.eventNames);

        clazz.prototype.remove = function() {
            if (this.$methods !== null) {
                var k = null;
                if (arguments.length === 0) {
                    for(k in this.$methods) {
                        if (this.$methods[k] !== undefined) {
                            this.$methods[k].length = 0;
                        }
                    }
                    this.$methods = {};
                } else {
                    var name = arguments.length > 1 || zebkit.isString(arguments[0]) ? arguments[0]
                                                                                     : null,
                        fn   = arguments.length > 1 ? arguments[1]
                                                    : (name === null ? arguments[0] : null),
                        i    = 0,
                        v    = null;

                    if (name !== null) {
                        if (this.$methods[name] !== undefined) {
                            if (fn === null) {
                                this.$methods[name].length = 0;
                                delete this.$methods[name];
                            } else {
                                v = this.$methods[name];
                                while ((i = v.indexOf(fn)) >= 0) {
                                    if (i % 2 > 0) {
                                        i--;
                                    }
                                    v.splice(i, 2);
                                }

                                if (v.length === 0) {
                                    delete this.$methods[name];
                                }
                            }
                        }
                    } else {
                        for (k in this.$methods) {
                            v = this.$methods[k];
                            while ((i = v.indexOf(fn)) >= 0) {
                                if (i % 2 > 0) {
                                    i--;
                                }
                                v.splice(i, 2);
                            }

                            if (v.length === 0) {
                                delete this.$methods[k];
                            }
                        }
                    }
                }
            }
        };

        clazz.prototype.hasEvent = function(nm) {
            return (this.$names !== undefined && this.$names[nm] !== undefined) || names[nm] !== undefined;
        };
    }

    return clazz;
};

/**
 * Listeners container class that can be handy to store number of listeners
 * for one type of event.
 * @param {String} [eventName] an event name the listeners container has been
 * created. By default "fired" is default event name. Event name is used to fire
 * the given event to a listener container.
 * @constructor
 * @class zebkit.Listeners
 * @example
 *
 *      // create container with a default event name
 *      var  container = new Listeners();
 *
 *      // register a listener
 *      var  listener = container.add(function(param1, param2) {
 *          // handle fired event
 *      });
 *
 *      ...
 *      // fire event
 *      container.fired(1, 2, 3);
 *
 *      // remove listener
 *      container.remove(listener);
 *
 * @extends zebkit.Listener
 */


/**
 * Add listener
 * @param {Function|Object} l a listener method or object.
 * @return {Function} a listener that has been registered in the container. The result should
 * be used to un-register the listener
 * @method  add
 */


/**
 * Remove listener or all registered listeners from the container
 * @param {Function} [l] a listener to be removed. If the argument has not been specified
 * all registered in the container listeners will be removed
 * @method  remove
 */
var Listeners = $NewListener();

/**
 * Event producer interface. This interface provides number of methods
 * to register, un-register, fire events. It follows on/off notion like
 * JQuery does it. It is expected an event producer class implementation
 * has a special field  "_" that keeps listeners.
 *
 *     var MyClass = zebkit.Class(zebkit.EventProducer, [
 *         function() {
 *             // "fired" events listeners container
 *             this._ = new zebkit.Listeners();
 *         }
 *     ]);
 *
 *     var a = new MyClass();
 *     a.on("fired", function(arg) {
 *         // handle "fired" events
 *     });
 *
 *     a.fire(10);
 *
 * @class zebkit.EventProducer
 * @interface zebkit.EventProducer
 */
var EventProducer = Interface([
    function $prototype() {
        // on(event, path, cb)  handle the given event for all elements identified with the path
        // on(cb)               handle all events
        // on(path | event, cb) handle the given event or all events for elements matched with the path


        /**
         * Register listener for the given events types or/and the given nodes in tree-like
         * structure or listen all events types.
         * @param {String} [eventName] an event type name to listen. If the event name is not passed
         * then listen all events types.
         * @param {String} [path] a xpath-like path to traversing elements in tree and register event
         * handlers for the found elements. The parameter can be used if the interface is implemented
         * with tree-like structure (for instance zebkit UI components).
         * @param {Function|Object} cb a listener method or an object that contains number of methods
         * to listen the specified events types.
         * @example
         *     var comp = new zebkit.ui.Panel();
         *     comp.add(new zebkit.ui.Button("Test 1").setId("c1"));
         *     comp.add(new zebkit.ui.Button("Test 2").setId("c2"));
         *     ...
         *     // register event handler for children components of "comp"
         *     comp.on("/*", function() {
         *         // handle button fired event
         *         ...
         *     });
         *
         *     // register event handler for button component with id equals "c1"
         *     comp.on("#c1", function() {
         *         // handle button fired event
         *         ...
         *     });
         *
         * @method on
         */
        this.on = function() {
            var cb = arguments[arguments.length - 1],  // callback or object
                pt = null,                             // path
                nm = null;                             // event name

            if (cb === null || (typeof cb === "string" || cb.constructor === String)) {
                throw new Error("Invalid event handler");
            }

            if (arguments.length === 1) {
                if (this._ === undefined) {
                    if (this.clazz.Listeners !== undefined) {
                        this._ = new this.clazz.Listeners();
                    } else {
                        return false;
                    }
                }
                return this._.add(cb);
            } else if (arguments.length === 2) {
                if (arguments[0] === null) {
                    throw new Error("Invalid event or path");
                } else if (arguments[0][0] === '.' || arguments[0][0] === '/' || arguments[0][0] === '#') { // a path detected
                    pt = arguments[0];
                } else {
                    if (this._ === undefined) {
                        if (this.clazz.Listeners !== undefined) {
                            this._ = new this.clazz.Listeners();
                        } else {
                            return false;
                        }
                    }
                    return this._.add(arguments[0], cb);
                }
            } else if (arguments.length === 3) {
                pt = arguments[1];
                nm = arguments[0];
                if (pt === null) {
                    if (this._ === undefined) {
                        if (this.clazz.Listeners !== undefined) {
                            this._ = new this.clazz.Listeners();
                        } else {
                            return false;
                        }
                    }
                    return this._.add(nm, cb);
                }
            }

            if (instanceOf(this, PathSearch) === false) {
                throw new Error("Path search is not supported");
            }

            this.byPath(pt, function(node) {
                // try to initiate
                if (node._ === undefined && node.clazz.Listeners !== undefined) {
                    node._ = new node.clazz.Listeners();
                }

                if (node._ !== undefined) {
                    if (nm !== null) {
                        if (node._[nm] !== undefined) {
                            node._.add(nm, cb);
                        }
                    } else {
                        node._.add(cb);
                    }
                }
                return false;
            });

            return cb;
        };

        // off()            remove all events handler
        // off(event)       remove the event handler
        // off(event, path)  remove the event handler for all nodes detected with the path
        // off(path)
        // off(cb)
        // off(path, cb)
        //
        /**
         * Stop listening the given event type.
         * @param {String} [eventName] an event type name to stop listening. If the event name is not passed
         * then stop listening all events types.
         * @param {String} [path] a xpath-like path to traversing elements in tree and stop listening
         * the event type for the found in the tree elements. The parameter can be used if the interface
         * is implemented with tree-like structure (for instance zebkit UI components).
         * @param [cb] remove the given event handler.
         * @method off
         */
        this.off = function() {
            var pt = null,  // path
                fn = null,  // handler
                nm = null;  // event name or listener

            if (arguments.length === 0) {
                if (this._ !== undefined) {
                    return this._.remove();
                } else {
                    return;
                }
            } else if (arguments.length === 1) {
                if (isString(arguments[0]) && (arguments[0][0] === '.' || arguments[0][0] === '/' || arguments[0][0] === '#')) {
                    pt = arguments[0];
                } else {
                    if (this._ !== undefined) {
                        return this._.remove(arguments[0]);
                    } else {
                        return;
                    }
                }
            } else if (arguments.length === 2) {
                if (isString(arguments[1])) { // detect path
                    pt = arguments[1];
                    nm = arguments[0];
                } else {
                    if (isString(arguments[1])) {
                        nm = arguments[1];
                    } else {
                        fn = arguments[1];
                    }

                    if (arguments[0][0] === '.' || arguments[0][0] === '/' || arguments[0][0] === '#') {
                        pt = arguments[0];
                    } else {
                        throw new Error("Path is expected");
                    }
                }
            }

            this.byPath(pt, function(node) {
                if (node._ !== undefined) {
                    if (fn !== null) {
                        node._.remove(fn);
                    } else if (nm !== null) {
                        if (node._[nm] !== undefined) {
                            node._.remove(nm);
                        }
                    } else {
                        node._.remove();
                    }
                }
                return false;
            });
        };

        /**
         * Fire event with the given parameters.
         * @param {String} name an event name
         * @param {String} [path]  a path if the event has to be send to multiple destination in the tree
         * @param {Object|Array}  [params] array of parameters or single parameter to be passed to an event
         * handler or handlers.
         * @method fire
         */
        this.fire = function(name) {
            if (arguments.length > 0 && arguments.length < 3) {
                if (this._ !== undefined) {
                    if (this._.hasEvent(name) === false) {
                        throw new Error("Listener doesn't support '" + name + "' event");
                    }

                    if (arguments.length === 2) {
                        Array.isArray(arguments[1]) ? this._[name].apply(this._, arguments[1])
                                                    : this._[name].call(this._, arguments[1]);
                    } else {
                        this._[name].call(this._);
                    }
                }
            } else if (arguments.length === 3) {
                var args = arguments[2];
                this.byPath(arguments[1], function(n) {
                    if (n._ !== undefined && n._.hasEvent(name)) {
                        var ec = n._;
                        if (args !== null && Array.isArray(args)) {
                            ec[name].apply(ec, args);
                        } else {
                            ec[name].call(ec, args);
                        }
                    }
                    return false;
                });
            } else {
                throw new Error("Invalid number of arguments");
            }
        };
    }
]);

// class instance method

/**
 * Extends zebkit.Class with the possibility to evaluate if the
 * given event is fired with the class.
 * @param {String} name an event name.
 * @method isEventFired
 * @for  zebkit.Class
 */
classTemplateProto.isEventFired = function(name) {
    if (this.clazz.Listeners === undefined) {
        return false;
    }

    if (arguments.length === 0) {
        name = "fired";
    }

    var names = this.clazz.Listeners.eventNames;
    if (names.length === 1) {
        return names[0] === name;
    }

    for(var i = 0; i < names.length; i++) {
        if (names[i] === name) {
            return true;
        }
    }
    return false;
};

/**
 * Extends zebkit.Class with the given events support.
 * @param {String} [args]* list of events names
 * @method events
 * @for  zebkit.Class
 */
classTemplateFields.events = function() {
    if (arguments.length === 0) {
        throw new Error("No an event name was found");
    }

    var args = Array.prototype.slice.call(arguments),
        c    = args.length;

    // collect events the class already declared
    if (this.Listeners !== undefined) {
        for (var i = 0; i < this.Listeners.eventNames.length; i++) {
            var en = this.Listeners.eventNames[i];
            if (args.indexOf(en) < 0) {
                args.push(en);
            }
        }
    }

    if (this.Listeners === undefined || c !== args.length) {
        this.Listeners = $NewListener.apply($NewListener, args);
    }

    if (this.isInherit(EventProducer) === false) {
        this.extend(EventProducer);
    }

    return this;
};


$export({
    "Event"          : Event,
    "Listeners"      : Listeners,
    "ListenersClass" : $NewListener,
    "EventProducer"  : EventProducer
});
/**
 * This class represents a font and provides basic font metrics like height, ascent. Using
 * the class developers can compute string width.
 *
 *     // plain font
 *     var f = new zebkit.Font("Arial", 14);
 *
 *     // bold font
 *     var f = new zebkit.Font("Arial", "bold", 14);
 *
 *     // defining font with CSS font name
 *     var f = new zebkit.Font("100px Futura, Helvetica, sans-serif");
 *
 * @constructor
 * @param {String} name a name of the font. If size and style parameters has not been passed
 * the name is considered as CSS font name that includes size and style
 * @param {String} [style] a style of the font: "bold", "italic", etc
 * @param {Integer} [size] a size of the font
 * @class zebkit.Font
 */
var Font = Class([
    function(family, style, size) {
        if (arguments.length === 1) {
            this.size = this.clazz.decodeSize(family);
            if (this.size === null) {
                // trim
                family = family.trim();

                // check if a predefined style has been used
                if (family === "bold" || family === "italic") {
                    this.style = family;
                } else {  // otherwise handle it as CSS-like font style
                    // try to parse font if possible
                    var re = /([a-zA-Z_\- ]+)?(([0-9]+px|[0-9]+em)\s+([,\"'a-zA-Z_ \-]+))?/,
                        m  = family.match(re);

                    if (m[4] !== undefined) {
                        this.family = m[4].trim();
                    }

                    if (m[3] !== undefined) {
                        this.size = m[3].trim();
                    }

                    if (m[1] !== undefined) {
                        this.style = m[1].trim();
                    }

                    this.s = family;
                }
            }
        } else if (arguments.length === 2) {
            this.family = family;
            this.size   = this.clazz.decodeSize(style);
            this.style  = this.size === null ? style : null;
        } else if (arguments.length === 3) {
            this.family = family;
            this.style  = style;
            this.size   = this.clazz.decodeSize(size);
        }

        if (this.size === null) {
            this.size = this.clazz.size + "px";
        }

        if (this.s === null) {
            this.s = ((this.style !== null) ? this.style + " ": "") +
                     this.size + " " +
                     this.family;
        }

        var mt = $zenv.fontMetrics(this.s);

        /**
         * Height of the font
         * @attribute height
         * @readOnly
         * @type {Integer}
         */
        this.height = mt.height;
    },

    function $clazz() {

        // default values
        this.family = "Arial, Helvetica";
        this.style  =  null;
        this.size   =  14;

        this.mergeable = false;

        this.decodeSize = function(s, defaultSize) {
            if (arguments.length < 2) {
                defaultSize = this.size;
            }

            if (typeof s === "string" || s.constructor === String) {
                var size = Number(s);
                if (isNaN(size)) {
                    var m = s.match(/^([0-9]+)(%)$/);
                    if (m !== null && m[1] !== undefined && m[2] !== undefined) {
                        size = Math.floor((defaultSize * parseInt(m[1], 10)) / 100);
                        return size + "px";
                    } else {
                        return /^([0-9]+)(em|px)$/.test(s) === true ? s : null;
                    }
                } else {
                    if (s[0] === '+') {
                        size = defaultSize + size;
                    } else if (s[0] === '-') {
                        size = defaultSize - size;
                    } else {
                        return size + "px";
                    }
                }
            }
            return s === null ? null : s + "px";
        };
    },

    function $prototype(clazz) {
        this.s = null;

        /**
         *  Font family.
         *  @attribute family
         *  @type {String}
         *  @default null
         */
        this.family = clazz.family;

        /**
         *  Font style (for instance "bold").
         *  @attribute style
         *  @type {String}
         *  @default null
         */
        this.style = clazz.style;
        this.size  = clazz.size;

        /**
         * Returns CSS font representation
         * @return {String} a CSS representation of the given Font
         * @method toString
         * @for zebkit.Font
         */
        this.toString = function() {
            return this.s;
        };

        /**
         * Compute the given string width in pixels basing on the
         * font metrics.
         * @param  {String} s a string
         * @return {Integer} a string width
         * @method stringWidth
         */
        this.stringWidth = function(s) {
            if (s.length === 0) {
                return 0;
            } else {
                var fm = $zenv.fontMeasure;
                if (fm.font !== this.s) {
                    fm.font = this.s;
                }

                return Math.round(fm.measureText(s).width);
            }
        };

        /**
         * Calculate the specified substring width
         * @param  {String} s a string
         * @param  {Integer} off fist character index
         * @param  {Integer} len length of substring
         * @return {Integer} a substring size in pixels
         * @method charsWidth
         * @for zebkit.Font
         */
        this.charsWidth = function(s, off, len) {
            var fm = $zenv.fontMeasure;
            if (fm.font !== this.s) {
                fm.font = this.s;
            }

            return Math.round((fm.measureText(len === 1 ? s[off]
                                                        : s.substring(off, off + len))).width );
        };

        /**
         * Resize font and return new instance of font class with new size.
         * @param  {Integer | String} size can be specified in pixels as integer value or as
         * a percentage from the given font:
         * @return {zebkit.Font} a font
         * @for zebkit.Font
         * @method resize
         * @example
         *
         * ```javascript
         * var font = new zebkit.Font(10); // font 10 pixels
         * font = font.resize("200%"); // two times higher font
         * ```
         */
        this.resize = function(size) {
            var nsize = this.clazz.decodeSize(size, this.height);
            if (nsize === null) {
                throw new Error("Invalid font size : " + size);
            }
            return new this.clazz(this.family, this.style, nsize);
        };

        /**
         * Restyle font and return new instance of the font class
         * @param  {String} style a new style
         * @return {zebkit.Font} a font
         * @method restyle
         */
        this.restyle = function(style) {
            return new this.clazz(this.family, style, this.height + "px");
        };
    }
]);

function $font() {
    if (arguments.length === 1) {
        if (instanceOf(arguments[0], Font)) {
            return arguments[0];
        } if (Array.isArray(arguments[0])) {
            return Font.newInstance.apply(Font, arguments[0]);
        } else if (arguments[0] !== null) {
            return new Font(arguments[0]);
        } else {
            return null;
        }
    } else if (arguments.length > 1) {
        return Font.newInstance.apply(Font, arguments);
    } else {
        throw Error("No an argument has been defined");
    }
}

$export( { "Font" : Font }, $font );

function $ls(callback, all) {
    for (var k in this) {
        var v = this[k];
        if (this.hasOwnProperty(k) && (v instanceof Package) === false)  {
            if ((k[0] !== '$' && k[0] !== '_') || all === true) {
                if (callback.call(this, k, this[k]) === true) {
                    return true;
                }
            }
        }
    }
    return false;
}

function $lsall(fn) {
    return $ls.call(this, function(k, v) {
        if (v === undefined) {
            throw new Error(fn + "," + k);
        }
        if (v !== null && v.clazz === Class) {
            // class is detected, set the class name and ref to the class package
            if (v.$name === undefined) {
                v.$name = fn + k;
                v.$pkg  = getPropertyValue($global, fn.substring(0, fn.length - 1));

                if (v.$pkg === undefined) {
                    throw new ReferenceError(fn);
                }
            }
            return $lsall.call(v, v.$name + ".");
        }
    });
}

/**
 *  Package is a special class to declare zebkit packages. Global variable "zebkit" is
 *  root package for all other packages. To declare a new package use "zebkit" global
 *  variable:
 *
 *      // declare new "mypkg" package
 *      zebkit.package("mypkg", function(pkg, Class) {
 *          // put the package entities in
 *          pkg.packageVariable = 10;
 *          ...
 *      });
 *      ...
 *
 *      // now we can access package and its entities directly
 *      zebkit.mypkg.packageVariable
 *
 *      // or it is preferable to wrap a package access with "require"
 *      // method
 *      zebkit.require("mypkg", function(mypkg) {
 *          mypkg.packageVariable
 *      });
 *
 *  @class zebkit.Package
 *  @constructor
 */
function Package(name, parent) {
    /**
     * URL the package has been loaded
     * @attribute $url
     * @readOnly
     * @type {String}
     */
    this.$url = null;

    /**
     * Name of the package
     * @attribute $name
     * @readOnly
     * @type {String}
     */
    this.$name = name;

    /**
     * Package configuration parameters.
     * @attribute $config
     * @readOnly
     * @private
     * @type {Object}
     */
    this.$config = {};

    /**
     * Package ready promise.
     * @attribute $ready
     * @type {zebkit.DoIt}
     * @private
     */
    this.$ready = new DoIt();

    /**
     * Reference to a parent package
     * @attribute $parent
     * @private
     * @type {zebkit.Package}
     */
    this.$parent = arguments.length < 2 ? null : parent;
}

/**
 * Get or set configuration parameter.
 * @param {String} [name] a parameter name.
 * @param {Object} [value] a parameter value.
 * @param {Boolean} [overwrite] boolean flag that indicates if the
 * parameters value have to be overwritten if it exists
 * @method  config
 */
Package.prototype.config = function(name, value, overwrite) {
    if (arguments.length === 0) {
        return this.$config;
    } else if (arguments.length === 1 && isString(arguments[0])) {
        return this.$config[name];
    } else  {
        if (isString(arguments[0])) {
            var old = this.$config[name];
            if (value === undefined) {
                delete this.$config[name];
            } else if (arguments.length < 3 || overwrite === true) {
                this.$config[name] = value;
            } else if (this.$config.hasOwnProperty(name) === false) {
                this.$config[name] = value;
            }
            return old;
        } else {
            overwrite = arguments.length > 1 ? value : false;
            for (var k in arguments[0]) {
                this.config(k, arguments[0][k], overwrite);
            }
        }
    }
};

/**
 * Detect the package location and store the location into "$url"
 * package field
 * @private
 * @method $detectLocation
 */
Package.prototype.$detectLocation = function() {
    if (typeof __dirname !== 'undefined') {
        this.$url = __dirname;
    } else if (typeof document !== "undefined") {
        //
        var s  = document.getElementsByTagName('script'),
            ss = s[s.length - 1].getAttribute('src'),
            i  = ss === null ? -1 : ss.lastIndexOf("/"),
            a  = document.createElement('a');

        a.href = (i > 0) ? ss.substring(0, i + 1)
                         : document.location.toString();

        this.$url = a.href.toString();
    }
};

/**
 * Get full name of the package. Full name includes not the only the given
 * package name, but also all parent packages separated with "." character.
 * @return {String} a full package name
 * @method fullname
 */
Package.prototype.fullname = function() {
    var n = [ this.$name ], p = this;
    while (p.$parent !== null) {
        p = p.$parent;
        n.unshift(p.$name);
    }
    return n.join(".");
};

/**
 * Find a package with the given file like path relatively to the given package.
 * @param {String} path a file like path
 * @return {String} path a path
 * @example
 *
 *      // declare "zebkit.test" package
 *      zebkit.package("test", function(pkg, Class) {
 *          ...
 *      });
 *      ...
 *
 *      zebkit.require("test", function(test) {
 *          var parent = test.cd(".."); // parent points to zebkit package
 *          ...
 *      });
 *
 * @method cd
 */
Package.prototype.cd = function(path) {
    if (path[0] === '/') {
        path = path.substring(1);
    }

    var paths = path.split('/'),
        pk    = this;

    for (var i = 0; i < paths.length; i++) {
        var pn = paths[i];
        if (pn === "..") {
            pk = pk.$parent;
        } else {
            pk = pk[pn];
        }

        if (pk === undefined || pk === null) {
            throw new Error("Package path '" + path + "' cannot be resolved");
        }
    }

    return pk;
};

/**
 * List the package sub-packages.
 * @param  {Function} callback    callback function that gets a sub-package name and the
 * sub-package itself as its arguments
 * @param  {boolean}  [recursively]  indicates if sub-packages have to be traversed recursively
 * @method packages
 */
Package.prototype.packages = function(callback, recursively) {
    for (var k in this) {
        var v = this[k];
        if (k !== "$parent" && this.hasOwnProperty(k) && v instanceof Package) {

            if (callback.call(this, k, v) === true || (recursively === true && v.packages(callback, recursively) === true)) {
                return true;
            }
        }
    }
    return false;
};

/**
 * Get a package by the specified name.
 * @param  {String} name a package name
 * @return {zebkit.Package} a package
 * @method byName
 */
Package.prototype.byName = function(name) {
    if (this.fullname() === name) {
        return this;
    } else  {
        var i = name.indexOf('.');
        if (i > 0) {
            var vv = getPropertyValue(this, name.substring(i + 1), false);
            return vv === undefined ? null : vv;
        } else {
            return null;
        }
    }
};

/**
 * List classes, variables and interfaces defined in the given package.
 * If second parameter "all" passed to the method is false, the method
 * will skip package entities whose name starts from "$" or "_" character.
 * These entities are considered as private ones. Pay attention sub-packages
 * are not listed.
 * @param  {Function} cb a callback method that get the package entity key
 * and the entity value as arguments.
 * @param  {Boolean}  [all] flag that specifies if private entities are
 * should be listed.
 * @method ls
 */
Package.prototype.ls = function(cb, all) {
    return $ls.call(this, cb, all);
};

/**
 * Build import JS code string that can be evaluated in a local space to make visible
 * the given package or packages classes, variables and methods.
 * @example
 *
 *     (function() {
 *         // make visible variables, classes and methods declared in "zebkit.ui"
 *         // package in the method local space
 *         eval(zebkit.import("ui"));
 *
 *         // use imported from "zebkit.ui.Button" class without necessity to specify
 *         // full path to it
 *         var bt = new Button("Ok");
 *     })();
 *
 * @param {String} [pkgname]* names of packages to be imported
 * @return {String} an import string to be evaluated in a local JS space
 * @method  import
 * @deprecated Usage of the method has to be avoided. Use zebkit.require(...) instead.
 */
Package.prototype.import = function() {
    var code = [];
    if (arguments.length > 0) {
        for(var i = 0; i < arguments.length; i++) {
            var v = getPropertyValue(this, arguments[i]);
            if ((v instanceof Package) === false) {
                throw new Error("Package '" + arguments[i] + " ' cannot be found");
            }
            code.push(v.import());
        }

        return code.length > 0 ?  code.join(";") : null;
    } else {
        var fn = this.fullname();
        this.ls(function(k, v) {
            code.push(k + '=' + fn + '.' + k);
        });

        return code.length > 0 ?  "var " + code.join(",") + ";" : null;
    }
};

/**
 * This method has to be used to start building a zebkit application. It
 * expects a callback function where an application code has to be placed and
 * number of required for the application packages names.  The call back gets
 * the packages instances as its arguments. The method guarantees the callback
 * is called at the time zebkit and requested packages are loaded, initialized
 * and ready to be used.
 * @param {String} [packages]* name or names of packages to make visible
 * in callback method
 * @param {Function} [callback] a method to be called. The method is called
 * in context of the given package and gets requested packages passed as the
 * method arguments in order they have been requested.
 * @method  require
 * @example
 *
 *     zebkit.require("ui", function(ui) {
 *         var b = new ui.Button("Ok");
 *         ...
 *     });
 *
 */
Package.prototype.require = function() {
    var pkgs  = [],
        $this = this,
        fn    = arguments[arguments.length - 1];

    if (typeof fn !== 'function') {
        throw new Error("Invalid callback function");
    }

    for(var i = 0; isString(arguments[i]) && i < arguments.length; i++) {
        var pkg = getPropertyValue(this, arguments[i]);
        if ((pkg instanceof Package) === false) {
            throw new Error("Package '" + arguments[i] + "' cannot be found");
        }
        pkgs.push(pkg);
    }

    return this.then(function() {
        fn.apply($this, pkgs);
    });
};

/**
 * Detect root package.
 * @return {zebkit.Package} a root package
 * @method getRootPackage
 */
Package.prototype.getRootPackage = function() {
    var rootPkg = this;
    while (rootPkg.$parent !== null) {
        rootPkg = rootPkg.$parent;
    }
    return rootPkg;
};

var $textualFileExtensions = [
        "txt", "json", "htm", "html", "md", "properties", "conf", "xml", "java", "js", "css", "scss", "log"
    ],
    $imageFileExtensions = [
        "jpg", "jpeg", "png", "tiff", "gif", "ico", "exif", "bmp"
    ];

/**
 * This method loads resources (images, textual files, etc) and call callback
 * method with completely loaded resources as input arguments.
 * @example
 *
 *     zebkit.resources(
 *         "http://test.com/image1.jpg",
 *         "http://test.com/text.txt",
 *         function(image, text) {
 *             // handle resources here
 *             ...
 *         }
 *     );
 *
 * @param  {String} paths*  paths to resources to be loaded
 * @param  {Function} cb callback method that is executed when all listed
 * resources are loaded and ready to be used.
 * @method resources
 */
Package.prototype.resources = function() {
    var args  = Array.prototype.slice.call(arguments),
        $this = this,
        fn    = args.pop();

    if (typeof fn !== 'function') {
        throw new Error("Invalid callback function");
    }

    this.then(function() {
        for(var i = 0; i < args.length ; i++) {
            (function(path, jn) {
                var m    = path.match(/^(\<[a-z]+\>\s*)?(.*)$/),
                    type = "txt",
                    p    = m[2].trim();

                if (m[1] !== undefined) {
                    type = m[1].trim().substring(1, m[1].length - 1).trim();
                } else {
                    var li = p.lastIndexOf('.');
                    if (li > 0) {
                        var ext = p.substring(li + 1).toLowerCase();
                        if ($textualFileExtensions.indexOf(ext) >= 0) {
                            type = "txt";
                        } else if ($imageFileExtensions.indexOf(ext) >= 0) {
                            type = "img";
                        }
                    }
                }

                if (type === "img") {
                    $zenv.loadImage(p, function(img) {
                        jn(img);
                    }, function(img, e) {
                        jn(null);
                    });
                } else if (type === "txt") {
                    ZFS.GET(p).then(function(req) {
                        jn(req.responseText);
                    }).catch(function(e) {
                        jn(null);
                    });
                } else {
                    jn(null);
                }

            })(args[i], this.join());
        }
    }).then(function() {
        fn.apply($this, arguments);
    });
};

/**
 * This method helps to sync accessing to package entities with the
 * package internal state. For instance package declaration can initiate
 * loading resources that happens asynchronously. In this case to make sure
 * the package completed loading its configuration we should use package
 * "then" method.
 * @param  {Function} f a callback method where we can safely access the
 * package entities
 * @chainable
 * @private
 * @example
 *
 *     zebkit.then(function() {
 *         // here we can make sure all package declarations
 *         // are completed and we can start using it
 *     });
 *
 * @method  then
 */
Package.prototype.then = function(f) {
    this.$ready.then(f).catch(function(e) {
        dumpError(e);
        // re-start other waiting tasks
        this.restart();
    });
    return this;
};

Package.prototype.join = function() {
    return this.$ready.join.apply(this.$ready, arguments);
};

/**
 * Method that has to be used to declare packages.
 * @param  {String}   name     a name of the package
 * @param  {Function} [callback] a call back method that is called in package
 * context. The method has to be used to populate the given package classes,
 * interfaces and variables.
 * @param  {String|Boolean} [path] a path to configuration JSON file or boolean flag that says
 * to perform configuration using package as configuration name
 * @example
 *     // declare package "zebkit.log"
 *     zebkit.package("log", function(pkg) {
 *         // declare the package class Log
 *         pkg.Log = zebkit.Class([
 *              function error() { ... },
 *              function warn()  { ... },
 *              function info()  { ... }
 *         ]);
 *     });
 *
 *     // later on you can use the declared package stuff as follow
 *     zebkit.require("log", function(log) {
 *         var myLog = new log.Log();
 *         ...
 *         myLog.warn("Warning");
 *     });
 *
 * @return {zebkit.Package} a package
 * @method package
 */
Package.prototype.package = function(name, callback, path) {
    // no arguments than return the package itself
    if (arguments.length === 0) {
        return this;
    } else {
        var target = this;

        if (typeof name !== 'function') {
            if (name === undefined || name === null) {
                throw new Error("Null package name");
            }

            name = name.trim();
            if (name.match(/^[a-zA-Z_][a-zA-Z0-9_]+(\.[a-zA-Z_][a-zA-Z0-9_]+)*$/) === null) {
                throw new Error("Invalid package name '" + name + "'");
            }

            var names = name.split('.');
            for(var i = 0, k = names[0]; i < names.length; i++, k = k + '.' + names[i]) {
                var n = names[i],
                    p = target[n];

                if (p === undefined) {
                    p = new Package(n, target);
                    target[n] = p;
                } else if ((p instanceof Package) === false) {
                    throw new Error("Requested package '" + name +  "' conflicts with variable '" + n + "'");
                }
                target = p;
            }
        } else {
            path     = callback;
            callback = name;
        }

        // detect url later then sooner since
        if (target.$url === null) {
            target.$detectLocation();
        }

        if (typeof callback === 'function') {
            this.then(function() {
                callback.call(target, target, typeof Class !== 'undefined' ? Class : null);
            }).then(function() {
                // initiate configuration loading if it has been requested
                if (path !== undefined && path !== null) {
                    var jn = this.join();
                    if (path === true) {
                        var fn = target.fullname();
                        path = fn.substring(fn.indexOf('.') + 1) + ".json";
                        target.configWithRs(path, jn);
                    } else {
                        target.configWith(path, jn);
                    }
                }
            }).then(function(r) {
                if (r instanceof Error) {
                    this.error(r);
                } else {
                    // initiate "clazz.$name" resolving
                    $lsall.call(target, target.fullname() + ".");
                }
            });
        }

        return target;
    }
};


function resolvePlaceholders(path, env) {
    // replace placeholders in dir path
    var ph = path.match(/\%\{[a-zA-Z$][a-zA-Z0-9_$.]*\}/g);
    if (ph !== null) {
        for (var i = 0; i < ph.length; i++) {
            var p = ph[i],
                v = env[p.substring(2, p.length - 1)];

            if (v !== null && v !== undefined) {
                path = path.replace(p, v);
            }
        }
    }
    return path;
}

/**
 * Configure the given package with the JSON.
 * @param  {String | Object} path a path to JSON or JSON object
 * @param  {Function} [cb] a callback method
 * @method configWith
 */
Package.prototype.configWith = function(path, cb) {
    // catch error to keep passed callback notified
    try {
        if ((path instanceof URI || isString(path)) && URI.isAbsolute(path) === false) {
            path = URI.join(this.$url, path);
        }
    } catch(e) {
        if (arguments.length > 1 && cb !== null) {
            cb.call(this, e);
            return;
        } else {
            throw e;
        }
    }

    var $this = this;
    if (arguments.length > 1 && cb !== null) {
        new Zson($this).then(path, function() {
            cb.call(this, path);
        }).catch(function(e) {
            cb.call(this, e);
        });
    } else {
        this.getRootPackage().then(function() { // calling the guarantees it will be called when previous actions are completed
            this.till(new Zson($this).then(path)); // now we can trigger other loading action
        });
    }
};

/**
 * Configure the given package with the JSON.
 * @param  {String | Object} path a path to JSON or JSON object
 * @param  {Function} [cb] a callback
 * @method configWithRs
 */
Package.prototype.configWithRs = function(path, cb) {
    if (URI.isAbsolute(path)) {
        throw new Error("Absolute path cannot be used");
    }

    var pkg = this;
    // detect root package (common sync point) and package that
    // defines path to resources
    while (pkg !== null && (pkg.$config.basedir === undefined || pkg.$config.basedir === null)) {
        pkg = pkg.$parent;
    }

    if (pkg === null) {
        path = URI.join(this.$url, "rs", path);
    } else {
        // TODO: where config placeholders have to be specified
        path = URI.join(resolvePlaceholders(pkg.$config.basedir, pkg.$config), path);
    }

    return arguments.length > 1 ? this.configWith(path, cb)
                                : this.configWith(path);
};


$export(Package);
/**
 * This is the core package that provides powerful easy OOP concept, packaging
 * and number of utility methods. The package doesn't have any dependencies
 * from others zebkit packages and can be used independently. Briefly the
 * package possibilities are listed below:

   - **easy OOP concept**. Use "zebkit.Class" and "zebkit.Interface" to declare
     classes and interfaces

    ```JavaScript
        // declare class A
        var ClassA = zebkit.Class([
            function() { // class constructor
                ...
            },
            // class method
            function a(p1, p2, p3) { ... }
        ]);

        var ClassB = zebkit.Class(ClassA, [
            function() {  // override cotoString.nanstructor
                this.$super(); // call super constructor
            },

            function a(p1, p2, p3) { // override method "a"
                this.$super(p1, p2, p3);  // call super implementation of method "a"
            }
        ]);

        var b = new ClassB(); // instantiate classB
        b.a(1,2,3); // call "a"

        // instantiate anonymous class with new method "b" declared and
        // overridden method "a"
        var bb = new ClassB([
            function a(p1, p2, p3) { // override method "a"
                this.$super(p1, p2, p3);  // call super implementation of method "a"
            },

            function b() { ... } // declare method "b"
        ]);

        b.a();
        b.b();
    ```

   - **Packaging.** Zebkit uses Java-like packaging system where your code is bundled in
      the number of hierarchical packages.

    ```JavaScript
        // declare package "zebkit.test"
        zebkit.package("test", function(pkg) {
            // declare class "Test" in the package
            pkg.Test = zebkit.Class([ ... ]);
        });

        ...
        // Later on use class "Test" from package "zebkit.test"
        zebkit.require("test", function(test) {
            var test = new test.Test();
        });
    ```

    - **Resources loading.** Resources should be loaded with a special method to guarantee
      its proper loading in zebkit sequence and the loading completeness.

    ```JavaScript
        // declare package "zebkit.test"
        zebkit.resources("http://my.com/test.jpg", function(img) {
            // handle completely loaded image here
            ...
        });

        zebkit.package("test", function(pkg, Class) {
            // here we can be sure all resources are loaded and ready
        });
    ```

   - **Declaring number of core API method and classes**
      - **"zebkit.DoIt"** - improves Promise like alternative class
      - **"zebkit.URI"** - URI helper class
      - **"zebkit.Dummy"** - dummy class
      - **instanceOf(...)** method to evaluate zebkit classes and and interfaces inheritance.
        The method has to be used instead of JS "instanceof" operator to provide have valid
        result.
      - **zebkit.newInstance(...)** method
      - **zebkit.clone(...)**  method
      - etc

 * @class zebkit
 * @access package
 */

// =================================================================================================
//
//   Zebkit root package declaration
//
// =================================================================================================
var zebkit = new Package("zebkit");

/**
 * Reference to zebkit environment. Environment is basic, minimal API
 * zebkit and its components require.
 * @for  zebkit
 * @attribute environment
 * @readOnly
 * @type {Environment}
 */

// declaring zebkit as a global variable has to be done before calling "package" method
// otherwise the method cannot find zebkit to resolve class names
//
// nodejs
if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = zebkit;
}

$global.zebkit = zebkit;

// collect exported entities in zebkit package space
zebkit.package(function(pkg) {
    for(var exp in $exports) {
        pkg[exp] = $exports[exp];
    }
});

if ($isInBrowser) {

    // collect query string parameters
    try {
        var uri = new URI(document.URL);
        if (uri.qs !== null) {
            var params = URI.parseQS(uri.qs);
            for (var k in params) {
                zebkit.config(k, URI.decodeQSValue(params[k]));
            }

            var cacheBusting = zebkit.config("zson.cacheBusting");
            if (cacheBusting !== undefined && cacheBusting !== null) {
                Zson.prototype.cacheBusting = cacheBusting;
            }
        }
    } catch(e) {
        dumpError(e);
    }

    zebkit.then(function() {
        var jn        = this.join(),
            $interval = $zenv.setInterval(function () {
            if (document.readyState === "complete") {
                $zenv.clearInterval($interval);
                jn(zebkit);
            }
        }, 50);
    });
}
})();