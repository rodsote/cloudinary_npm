require('dotenv').load(silent: true)
https = require('https')
http = require('http')
expect = require("expect.js")
sinon = require('sinon')
cloudinary = require("../cloudinary")
fs = require('fs')
Q = require('q')
path = require('path');
isFunction = require('lodash/isFunction')
at = require('lodash/at')
uniq = require('lodash/uniq')
ClientRequest = require('_http_client').ClientRequest
require('jsdom-global')()

helper = require("./spechelper")
TEST_TAG        = helper.TEST_TAG
IMAGE_FILE      = helper.IMAGE_FILE
LARGE_RAW_FILE  = helper.LARGE_RAW_FILE
LARGE_VIDEO     = helper.LARGE_VIDEO
EMPTY_IMAGE     = helper.EMPTY_IMAGE
RAW_FILE        = helper.RAW_FILE
UPLOAD_TAGS     = helper.UPLOAD_TAGS
uploadImage    = helper.uploadImage

describe "uploader", ->
  before "Verify Configuration", ->
    config = cloudinary.config(true)
    if(!(config.api_key && config.api_secret))
      expect().fail("Missing key and secret. Please set CLOUDINARY_URL.")

  @timeout helper.TIMEOUT_LONG
  after ->
    config = cloudinary.config(true)
    if(!(config.api_key && config.api_secret))
      expect().fail("Missing key and secret. Please set CLOUDINARY_URL.")
    Q.allSettled [
      cloudinary.v2.api.delete_resources_by_tag(helper.TEST_TAG) unless cloudinary.config().keep_test_products
      cloudinary.v2.api.delete_resources_by_tag(helper.TEST_TAG, resource_type: "video") unless cloudinary.config().keep_test_products
    ]

  beforeEach ->
    cloudinary.config(true)

  it "should successfully upload file", () ->
    @timeout helper.TIMEOUT_LONG
    uploadImage()
    .then (result)->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)

  it "should successfully upload url", () ->
    cloudinary.v2.uploader.upload("http://cloudinary.com/images/old_logo.png", tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)

  describe "rename", ()->
    @timeout helper.TIMEOUT_LONG
    it "should successfully rename a file", () ->
      uploadImage()
      .then (result)->
        cloudinary.v2.uploader.rename(result.public_id, result.public_id+"2")
        .then ()-> result.public_id
      .then (public_id)->
        cloudinary.v2.api.resource(public_id+"2")

    it "should not rename to an existing public_id", ()->
      Promise.all [
        uploadImage()
        uploadImage()
      ]
      .then (results)->
        cloudinary.v2.uploader.rename(results[0].public_id, results[1].public_id)
      .then ()-> expect().fail()
      .catch (error)-> expect(error).to.be.ok()

    it "should allow to rename to an existing ID, if overwrite is true", ()->
      Promise.all [
        uploadImage()
        uploadImage()
      ]
      .then (results)->
        cloudinary.v2.uploader.rename(results[0].public_id, results[1].public_id, overwrite: true)
      .then ({public_id})->
        cloudinary.v2.api.resource(public_id)
      .then ({format})->
        expect(format).to.eql "png"

    context ":invalidate", ->
      spy = undefined
      xhr = undefined
      end = undefined
      before ->
        xhr = sinon.useFakeXMLHttpRequest()
        spy = sinon.spy(ClientRequest.prototype, 'write')
      after ->
        spy.restore()
        xhr.restore()
      it "should should pass the invalidate value in rename to the server", ()->
        cloudinary.v2.uploader.rename("first_id", "second_id", invalidate: true)
        expect(spy.calledWith(sinon.match((arg)-> arg.toString().match(/name="invalidate"/)))).to.be.ok()

  describe "destroy", ()->
    @timeout helper.TIMEOUT_MEDIUM
    it "should delete a resource", ()->
      uploadImage()
      .then (result)->
        public_id = result.public_id
        cloudinary.v2.uploader.destroy(public_id)
      .then (result)->
        expect(result.result).to.eql("ok")
        cloudinary.v2.api.resource(public_id)
      .then ()-> expect().fail()
      .catch (error)->
        expect(error).to.be.ok()

  it "should successfully call explicit api", () ->
    cloudinary.v2.uploader.explicit("sample", type: "upload", eager: [crop: "scale", width: "2.0"])
    .then (result)->
      url = cloudinary.utils.url "sample",
        type: "upload",
        crop: "scale",
        width: "2.0",
        format: "jpg",
        version: result["version"]
      expect(result.eager[0].url).to.eql(url)

  it "should support eager in upload", () ->
    @timeout helper.TIMEOUT_SHORT
    cloudinary.v2.uploader.upload(IMAGE_FILE, eager: [crop: "scale", width: "2.0"], tags: UPLOAD_TAGS)

  describe "custom headers", ()->
    it "should support custom headers in object format e.g. {Link: \"1\"}", () ->
      cloudinary.v2.uploader.upload(IMAGE_FILE, headers: {Link: "1"}, tags: UPLOAD_TAGS)

    it "should support custom headers as array of strings e.g. [\"Link: 1\"]", () ->
      cloudinary.v2.uploader.upload(IMAGE_FILE, headers: ["Link: 1"], tags: UPLOAD_TAGS)

  it "should successfully generate text image", () ->
    cloudinary.v2.uploader.text("hello world", tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.width).to.within(50,70)
      expect(result.height).to.within(5,15)

  it "should successfully upload stream", (done)->
    stream = cloudinary.v2.uploader.upload_stream tags: UPLOAD_TAGS, (error, result) ->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()
    file_reader = fs.createReadStream(IMAGE_FILE, {encoding: 'binary'})
    file_reader.on 'data', (chunk)-> stream.write(chunk,'binary')
    file_reader.on 'end', -> stream.end()

  describe "tags", ()->
    @timeout helper.TIMEOUT_MEDIUM
    it "should add tags to existing resources", () ->
      uploadImage()
      .then (result)->
        uploadImage().then (res)-> [result.public_id, res.public_id]
      .then ([firstId, secondId])->
        cloudinary.v2.uploader.add_tag("tag1", [firstId, secondId])
        .then ()-> [firstId, secondId]
      .then ([firstId, secondId])->
        cloudinary.v2.api.resource(secondId)
        .then (r1)->
          expect(r1.tags).to.contain("tag1")
        .then ()-> [firstId, secondId]
      .then ([firstId, secondId])->
        cloudinary.v2.uploader.remove_all_tags([firstId, secondId, 'noSuchId'])
        .then (result)-> [firstId, secondId, result]
      .then ([firstId, secondId, result])->
        expect(result["public_ids"]).to.contain(firstId)
        expect(result["public_ids"]).to.contain(secondId)
        expect(result["public_ids"]).to.not.contain('noSuchId')

    it "should keep existing tags when adding a new tag", ()->
      uploadImage()
      .then (result)->
        cloudinary.v2.uploader.add_tag("tag1", result.public_id)
        .then ()-> result.public_id
      .then (publicId)->
        cloudinary.v2.uploader.add_tag("tag2", publicId)
        .then ()-> publicId
      .then (publicId)->
        cloudinary.v2.api.resource(publicId)
      .then (result)->
        expect(result.tags).to.contain("tag1").and.contain( "tag2")

    it "should replace existing tag", ()->
      cloudinary.v2.uploader.upload(IMAGE_FILE, tags: ["tag1", "tag2", TEST_TAG])
      .then (result)->
        public_id = result.public_id
        cloudinary.v2.uploader.replace_tag( "tag3Å", public_id)
        .then ()-> public_id
      .then (public_id)-> # TODO this also tests non ascii characters
        cloudinary.v2.api.resource(public_id)
      .then (result)->
        expect(result.tags).to.eql(["tag3Å"])

  describe "context", ()->
    second_id = first_id = ''
    @timeout helper.TIMEOUT_MEDIUM
    before ()->
      Q.all [
        uploadImage()
        uploadImage()
        ]
      .spread (result1, result2)->
        first_id = result1.public_id
        second_id = result2.public_id
    it "should add context to existing resources", () ->
      cloudinary.v2.uploader.add_context('alt=testAlt|custom=testCustom', [first_id, second_id])
      .then ()->
        cloudinary.v2.uploader.add_context({alt2: "testAlt2", custom2: "testCustom2"}, [first_id, second_id])
      .then ()->
        cloudinary.v2.api.resource(second_id)
      .then ({context})->
        expect(context.custom.alt).to.equal('testAlt')
        expect(context.custom.alt2).to.equal('testAlt2')
        expect(context.custom.custom).to.equal('testCustom')
        expect(context.custom.custom2).to.equal('testCustom2')

        cloudinary.v2.uploader.remove_all_context([first_id, second_id, 'noSuchId'])
      .then ({public_ids})->
        expect(public_ids).to.contain(first_id)
        expect(public_ids).to.contain(second_id)
        expect(public_ids).to.not.contain('noSuchId')

        cloudinary.v2.api.resource(second_id)
      .then ({context})->
        expect(context).to.be undefined

    it "should upload with context containing reserved characters", ()->
      context = {key1: 'value1', key2: 'valu\e2', key3: 'val=u|e3', key4: 'val\=ue'}
      cloudinary.v2.uploader.upload(IMAGE_FILE, context: context)
      .then (result)->
        cloudinary.v2.api.resource(result.public_id, context: true)
      .then (result)->
        expect(result.context.custom).to.eql(context)

  it "should support timeouts", () ->
    # testing a 1ms timeout, nobody is that fast.
    cloudinary.v2.uploader.upload("http://cloudinary.com/images/old_logo.png", timeout: 1, tags: UPLOAD_TAGS)
    .then ()-> expect().fail()
    .catch ({error})->
      expect(error.http_code).to.eql(499)
      expect(error.message).to.eql("Request Timeout")

    
  it "should upload a file and base public id on the filename if use_filename is set to true", () ->
    @timeout helper.TIMEOUT_MEDIUM
    cloudinary.v2.uploader.upload(IMAGE_FILE, use_filename: yes, tags: UPLOAD_TAGS)
    .then ({public_id})->
      expect(public_id).to.match /logo_[a-zA-Z0-9]{6}/


  it "should upload a file and set the filename as the public_id if use_filename is set to true and unique_filename is set to false", ()->
    cloudinary.v2.uploader.upload(IMAGE_FILE, use_filename: yes, unique_filename: no, tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.public_id).to.eql "logo"

  describe "allowed_formats", ->
    it "should allow whitelisted formats", ()->
      cloudinary.v2.uploader.upload(IMAGE_FILE, allowed_formats: ["png"], tags: UPLOAD_TAGS)
      .then (result)->
        expect(result.format).to.eql("png")

    it "should prevent non whitelisted formats from being uploaded", ()->
      cloudinary.v2.uploader.upload(IMAGE_FILE, allowed_formats: ["jpg"], tags: UPLOAD_TAGS)
      .then ()-> expect().fail()
      .catch (error)->
        expect(error.http_code).to.eql(400)

    it "should allow non whitelisted formats if type is specified and convert to that type", ()->
      cloudinary.v2.uploader.upload(IMAGE_FILE, allowed_formats: ["jpg"], format: "jpg", tags: UPLOAD_TAGS)
      .then (result)->
        expect(result.format).to.eql("jpg")

  
  it "should allow sending face coordinates", ()->
    @timeout helper.TIMEOUT_LONG
    coordinates = [[120, 30, 109, 150], [121, 31, 110, 151]]
    out_coordinates = [[120, 30, 109, 51], [121, 31, 110, 51]] # coordinates are limited to the image dimensions
    different_coordinates = [[122, 32, 111, 152]]
    custom_coordinates = [1,2,3,4]
    cloudinary.v2.uploader.upload(IMAGE_FILE, face_coordinates: coordinates, faces: yes, tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.faces).to.eql(out_coordinates)
      cloudinary.v2.uploader.explicit(result.public_id, faces: true, face_coordinates: different_coordinates, custom_coordinates: custom_coordinates, type: "upload")
    .then (result)->
      expect(result.faces).not.to.be undefined
      cloudinary.v2.api.resource(result.public_id, faces: yes, coordinates: yes)
    .then (info)->
      expect(info.faces).to.eql(different_coordinates)
      expect(info.coordinates).to.eql(faces: different_coordinates, custom: [custom_coordinates])

  it "should allow sending context", ()->
    @timeout helper.TIMEOUT_LONG
    cloudinary.v2.uploader.upload(IMAGE_FILE, context: {caption: "some caption", alt: "alternative"}, tags: UPLOAD_TAGS)
    .then ({public_id})->
      cloudinary.v2.api.resource(public_id, context: true)
    .then ({context})->
      expect(context.custom.caption).to.eql("some caption")
      expect(context.custom.alt).to.eql("alternative")


       
  it "should support requesting manual moderation", () ->
    cloudinary.v2.uploader.upload(IMAGE_FILE, moderation: "manual", tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.moderation[0].status).to.eql("pending")
      expect(result.moderation[0].kind).to.eql("manual")

  it "should support requesting ocr analysis", ->
    cloudinary.v2.uploader.upload(IMAGE_FILE, ocr: "adv_ocr", tags: UPLOAD_TAGS)
    .then (result)->
      expect(result.info.ocr).to.have.key("adv_ocr")

    
  it "should support requesting raw conversion", ()->
    cloudinary.v2.uploader.upload(RAW_FILE, raw_convert: "illegal", resource_type: "raw", tags: UPLOAD_TAGS)
    .then ()-> expect().fail()
    .catch (error)->
      expect(error?).to.be true
      expect(error.message).to.contain "Raw convert is invalid"

    
  it "should support requesting categorization", ()->
    cloudinary.v2.uploader.upload(IMAGE_FILE, categorization: "illegal", tags: UPLOAD_TAGS)
    .then ()-> expect().fail()
    .catch (error)->
      expect(error?).to.be true

    
  it "should support requesting detection", ()->
    cloudinary.v2.uploader.upload(IMAGE_FILE, detection: "illegal", tags: UPLOAD_TAGS)
    .then ()-> expect().fail()
    .catch (error)->
      expect(error).not.to.be undefined
      expect(error.message).to.contain "Detection is invalid"

      
  it "should support requesting background_removal", ()->
    cloudinary.v2.uploader.upload(IMAGE_FILE, background_removal: "illegal", tags: UPLOAD_TAGS)
    .then ()-> expect().fail()
    .catch (error)->
      expect(error?).to.be true
      expect(error.message).to.contain "is invalid"

  describe "remote urls ", ()->
    writeSpy = undefined

    beforeEach ->
      writeSpy = sinon.spy(ClientRequest.prototype, 'write')

    afterEach ->
      writeSpy.restore()

    it "should send s3:// URLs to server", ()->
      cloudinary.v2.uploader.upload("s3://test/1.jpg", tags: UPLOAD_TAGS)
      sinon.assert.calledWith(writeSpy, sinon.match(helper.uploadParamMatcher('file', "s3://test/1.jpg")))
      
    it "should send gs:// URLs to server", ()->
      cloudinary.v2.uploader.upload("gs://test/1.jpg", tags: UPLOAD_TAGS)
      sinon.assert.calledWith(writeSpy, sinon.match(helper.uploadParamMatcher('file', "gs://test/1.jpg")))

    it "should send ftp:// URLs to server", ()->
      cloudinary.v2.uploader.upload("ftp://example.com/1.jpg", tags: UPLOAD_TAGS)
      sinon.assert.calledWith(writeSpy, sinon.match(helper.uploadParamMatcher('file', "ftp://example.com/1.jpg")))

      
  describe "upload_chunked", ()->
    @timeout helper.TIMEOUT_LONG * 10
    it "should specify chunk size", (done) ->
      fs.stat LARGE_RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large LARGE_RAW_FILE, {chunk_size: 7000000, timeout: helper.TIMEOUT_LONG, tags: UPLOAD_TAGS}, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("4c13724e950abcb13ec480e10f8541f5")
          done()
        true

    it "should return error if value is less than 5MB", (done)->
      fs.stat LARGE_RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large LARGE_RAW_FILE, {chunk_size: 40000, tags: UPLOAD_TAGS}, (error, result) ->
          expect(error.message).to.eql("All parts except EOF-chunk must be larger than 5mb")
          done()
        true

    it "should support uploading a small raw file", (done) ->
      fs.stat RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large RAW_FILE, tags: UPLOAD_TAGS, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("ffc265d8d1296247972b4d478048e448")
          done()
        true

    it "should support uploading a small image file", (done) ->
      fs.stat IMAGE_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_chunked IMAGE_FILE, tags: UPLOAD_TAGS, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("7dc60722d4653261648038b579fdb89e")
          done()
        true

    it "should support uploading large video files", () ->
      @timeout helper.TIMEOUT_LONG * 10
      writeSpy = sinon.spy(ClientRequest.prototype, 'write')
      stat = fs.statSync( LARGE_VIDEO)
      expect(stat).to.be.ok()
      Q.denodeify(cloudinary.v2.uploader.upload_chunked)( LARGE_VIDEO, {chunk_size: 6000000, resource_type: 'video', timeout: helper.TIMEOUT_LONG * 10, tags: UPLOAD_TAGS})
      .then (result)->
        expect(result.bytes).to.eql(stat.size)
        expect(result.etag).to.eql("ff6c391d26be0837ee5229885b5bd571")
        timestamps = writeSpy.args.map((a)-> a[0].toString())
          .filter((p) -> p.match(/timestamp/))
          .map((p) -> p.match(/"timestamp"\s+(\d+)/)[1])
        expect(timestamps.length).to.be.greaterThan(1)
        if process.versions.node && process.versions.node[0] == '4'
          timestamps.pop()  # hack - node 4 duplicates the last entry
        expect(uniq(timestamps)).to.eql(timestamps)
      .finally ->
        writeSpy.restore()

    it "should update timestamp for each chuck", ()->
        writeSpy = sinon.spy(ClientRequest.prototype, 'write')
        Q.denodeify(cloudinary.v2.uploader.upload_chunked)( LARGE_VIDEO, {chunk_size: 6000000, resource_type: 'video', timeout: helper.TIMEOUT_LONG * 10, tags: UPLOAD_TAGS})
        .then ->
          timestamps = writeSpy.args.map((a)-> a[0].toString())
            .filter((p) -> p.match(/timestamp/))
            .map((p) -> p.match(/"timestamp"\s+(\d+)/)[1])
          expect(timestamps.length).to.be.greaterThan(1)
          expect(uniq(timestamps)).to.eql(timestamps)
        .finally ->
          writeSpy.restore()

    it "should support uploading based on a url", (done) ->
      @timeout helper.TIMEOUT_MEDIUM
      cloudinary.v2.uploader.upload_large "http://cloudinary.com/images/old_logo.png", {tags: UPLOAD_TAGS}, (error, result) ->
        return done(new Error error.message) if error?
        expect(result.etag).to.eql("7dc60722d4653261648038b579fdb89e")
        done()
      true

  it "should support unsigned uploading using presets", ()->
    @timeout helper.TIMEOUT_LONG
    cloudinary.v2.api.create_upload_preset(folder: "upload_folder", unsigned: true, tags: UPLOAD_TAGS)
    .then (preset)->
      cloudinary.v2.uploader.unsigned_upload(IMAGE_FILE, preset.name, tags: UPLOAD_TAGS)
      .then (result)-> [preset.name, result.public_id]
    .then ([presetName, public_id])->
      expect(public_id).to.match /^upload_folder\/[a-z0-9]+$/
      cloudinary.v2.api.delete_upload_preset(presetName)

  it "should reject promise if error code is returned from the server", () ->
    cloudinary.v2.uploader.upload(EMPTY_IMAGE, tags: UPLOAD_TAGS)
    .then ->
      expect().fail("server should return an error when uploading an empty file")
    .catch (error)->
      expect(error.message.toLowerCase()).to.contain "empty"

  it "should successfully upload with pipes", (done) ->
    @timeout helper.TIMEOUT_LONG
    upload = cloudinary.v2.uploader.upload_stream tags: UPLOAD_TAGS, (error, result) ->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()
    file_reader = fs.createReadStream(IMAGE_FILE)
    file_reader.pipe(upload)

  it "should fail with http.Agent (non secure)", () ->
    @timeout helper.TIMEOUT_LONG
    expect(cloudinary.v2.uploader.upload_stream).withArgs({agent:new http.Agent},(error, result) ->
    ).to.throwError()

  it "should successfully override https agent", () ->
    upload = cloudinary.v2.uploader.upload_stream agent:new https.Agent, tags: UPLOAD_TAGS, (error, result) ->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
    file_reader = fs.createReadStream(IMAGE_FILE)
    file_reader.pipe(upload)

  context ":responsive_breakpoints", ->
    context ":create_derived with different transformation settings", ->
      before ->
        helper.setupCache()
      it 'should return a responsive_breakpoints in the response', ()->
        cloudinary.v2.uploader.upload IMAGE_FILE, responsive_breakpoints: [{
          transformation: {effect: "sepia"},
          format: "jpg",
          bytes_step: 20000,
          create_derived: true,
          min_width: 200,
          max_width: 1000,
          max_images: 20
        }, {
          transformation: {angle: 10},
          format: "gif",
          create_derived: true,
          bytes_step: 20000,
          min_width: 200,
          max_width: 1000,
          max_images: 20
        }], tags: UPLOAD_TAGS
        .then (result)->
          expect(result).to.have.key('responsive_breakpoints')
          expect(result.responsive_breakpoints).to.have.length(2)
          expect(at(result, "responsive_breakpoints[0].transformation")[0]).to.eql("e_sepia")
          expect(at(result, "responsive_breakpoints[0].breakpoints[0].url")[0]).to.match(/\.jpg$/)
          expect(at(result, "responsive_breakpoints[1].transformation")[0]).to.eql("a_10")
          expect(at(result, "responsive_breakpoints[1].breakpoints[0].url")[0]).to.match(/\.gif$/)
          result.responsive_breakpoints.map (bp)->
            format = path.extname(bp.breakpoints[0].url).slice(1)
            cached = cloudinary.Cache.get(
              result.public_id,
              {raw_transformation: bp.transformation, format})
            expect(cached).to.be.ok()
            expect(cached.length).to.be(bp.breakpoints.length)
            bp.breakpoints.forEach (o)->
              expect(cached).to.contain(o.width)

  describe "async upload", ->
    mocked = helper.mockTest()
    it "should pass `async` value to the server", ->
      cloudinary.v2.uploader.upload IMAGE_FILE, {async: true, transformation: {effect: "sepia"}}
      sinon.assert.calledWith mocked.write, sinon.match(helper.uploadParamMatcher("async", 1))

  describe "explicit", ->
    spy = undefined
    xhr = undefined
    before ->
      xhr = sinon.useFakeXMLHttpRequest()
      spy = sinon.spy(ClientRequest.prototype, 'write')
    after ->
      spy.restore()
      xhr.restore()

    describe ":invalidate", ->
      it "should should pass the invalidate value to the server", ()->
        cloudinary.v2.uploader.explicit "cloudinary", type: "twitter_name", eager: [crop: "scale", width: "2.0"], invalidate: true, tags: [TEST_TAG]
        sinon.assert.calledWith(spy, sinon.match(helper.uploadParamMatcher('invalidate', 1)))
    it "should support raw_convert", ->
      cloudinary.v2.uploader.explicit "cloudinary", raw_convert: "google_speech", tags: [TEST_TAG]
      sinon.assert.calledWith(spy, sinon.match(
        helper.uploadParamMatcher('raw_convert', 'google_speech')
      ))

  it "should create an image upload tag with required properties", () ->
    @timeout helper.TIMEOUT_LONG
    tag = cloudinary.v2.uploader.image_upload_tag "image_id", chunk_size: "1234"
    expect(tag).to.match(/^<input/)

    # Create an HTMLElement from the returned string to validate attributes
    fakeDiv = document.createElement('div');
    fakeDiv.innerHTML = tag;
    input_element = fakeDiv.firstChild;
    expect(input_element.tagName.toLowerCase()).to.be('input');
    expect(input_element.getAttribute("data-url")).to.be.ok();
    expect(input_element.getAttribute("data-form-data")).to.be.ok();
    expect(input_element.getAttribute("data-cloudinary-field")).to.match(/image_id/);
    expect(input_element.getAttribute("data-max-chunk-size")).to.match(/1234/);
    expect(input_element.getAttribute("class")).to.match(/cloudinary-fileupload/);
    expect(input_element.getAttribute("name")).to.be('file');
    expect(input_element.getAttribute("type")).to.be('file');

  describe "access_control", ()->
    writeSpy = undefined
    requestSpy = undefined
    options = undefined

    beforeEach ->
      writeSpy = sinon.spy(ClientRequest.prototype, 'write')
      requestSpy = sinon.spy(http, 'request')
      options = {
        public_id: helper.TEST_TAG,
        tags: [helper.UPLOAD_TAGS..., 'access_control_test']
      }

    afterEach ->
      requestSpy.restore()
      writeSpy.restore()

    acl = {
      access_type: 'anonymous',
      start: new Date(Date.UTC(2019,1,22, 16, 20, 57)),
      end: '2019-03-22 00:00 +0200'
    }
    acl_string =
      '{"access_type":"anonymous","start":"2019-02-22T16:20:57.000Z","end":"2019-03-22 00:00 +0200"}'

    it "should allow the user to define ACL in the upload parameters", ()->
      options.access_control = [acl]
      uploadImage(options).then (resource)=>
        sinon.assert.calledWith(writeSpy, sinon.match(
          helper.uploadParamMatcher('access_control', "[#{acl_string}]")
        ))
        expect(resource).to.have.key('access_control')
        response_acl = resource["access_control"]
        expect(response_acl.length).to.be(1)
        expect(response_acl[0]["access_type"]).to.be("anonymous")
        expect(Date.parse(response_acl[0]["start"])).to.be(Date.parse(acl.start))
        expect(Date.parse(response_acl[0]["end"])).to.be(Date.parse(acl.end))


