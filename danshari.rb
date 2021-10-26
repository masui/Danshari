require 'exifr/jpeg'
require 'find'
require 'json'
require 'digest/md5'
require 'gyazo'

class Danshari
  attr :home, true
  attr_reader :id

  def initialize(list)
    @home = ENV['HOME']
    @id = Time.now.strftime('%Y%m%d%H%M%S')
    @allfiles = []
    @allitems = []

    token = ENV['GYAZO_TOKEN'] # .bash_profileなどに書いてある
    @gyazo = Gyazo::Client.new access_token: token

    list.each { |item|
      if File.exist?(item)
        @allitems.push(item)
        if File.directory?(item)
          puts "file <#{item}> is directory"
        end
        Find.find(item) {|f|
          if File.file?(f)
            @allfiles.push f
          end
        }
      end
    }
  end

  def upload(file)
    STDERR.puts "ruby #{$home}/bin/upload #{file}"
    uploadurl = `ruby #{home}/bin/upload #{file}`.chomp.split(/\n/)[2] # ここいい加減
    STDERR.puts uploadurl
    uploadurl
  end

  def modtime(file)
    time = File.mtime(file).strftime('%Y%m%d%H%M%S')
  end

  def general_attr(file)
    attr = {}

    attr['filename'] = file
    attr['fullname'] = File.expand_path(file)
    attr['basename'] = File.basename(file)

    # MD5値
    attr['md5'] = Digest::MD5.new.update(File.read(file)).to_s

    # 時刻
    attr['time'] = modtime(file)
    if file =~ /(\w+)\.(jpg|jpeg)/i
      begin
        exif = EXIFR::JPEG.new(file)
        t = exif.date_time
        if t
          attr['time'] = t.strftime("%Y%m%d%H%M%S")
        end
      rescue
      end
    end

    # サイズ
    attr['size'] = File.size(file)

    attr
  end

  def exec
    attrs = []
    @allfiles.each { |file|
      attr = general_attr(file)

      # 特殊属性を追加
      if file =~ /\.(jpg|jpeg|png)$/i
        attr['time'] =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/
        time = Time.local($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,$6.to_i)
        
        STDERR.puts "upload #{file} to Gyazo..."
        res = @gyazo.upload imagefile: file, created_at: time
        gyazourl = res[:permalink_url]

        attr['gyazourl'] = gyazourl
      elsif file =~ /\.pdf$/i
        attr['time'] =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/
        time = Time.local($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,$6.to_i)
        
        system "convert -density 300 -geometry 1000 '#{file}[0]' /tmp/danshari.jpg" # pdfimagesの方がいいのかも?
        
        STDERR.puts "upload /tmp/danshari to Gyazo..."
        res = @gyazo.upload imagefile: "/tmp/danshari.jpg", created_at: time
        gyazourl = res[:permalink_url]

        attr['gyazourl'] = gyazourl
      end

      # GPS情報
      if file =~ /\.(jpg|jpeg)$/i
        begin
          exif = EXIFR::JPEG.new(file)
          d = exif.gps_longitude
          if d
            long = d[0] + d[1] / 60 + d[2] / 3600
            d = exif.gps_latitude
            lat = d[0] + d[1] / 60 + d[2] / 3600
            mapline = "[#{exif.gps_latitude_ref}#{lat.to_f},#{exif.gps_longitude_ref}#{long.to_f},Z14]"
            attr['mapline'] = mapline
          end
        rescue
        end
      end

      # テキストデータ
      begin
        if `file #{file}`.force_encoding("UTF-8") =~ /text/
          text = File.read(file).split(/\n/)[0,10]
          attr['text'] = text
        end
      rescue
      end

      attr['uploadurl'] = upload(file)
      
      attrs.push(attr)
    }

    # JSON生成
    data = {}
    pages = []
    attrs.each { |attr|
      obj = {}
      title = attr['basename']
      title += " - #{attr['md5'][0,6]}" if title !~ /[0-9a-f]{32}/
      obj['title'] = title

      lines = []
      lines.push(title)
      if attr['text']
        attr['text'].each { |line|
          lines.push(">#{line}")
        }
        lines.push("")
      end
      lines.push(attr['mapline']) if attr['mapline']
      lines.push("[#{attr['fullname']} #{attr['uploadurl']}]")
      lines.push("Date: #{attr['time']}") if attr['time']
      lines.push("Size: #{attr['size']}") if attr['size']
      lines.push("[#{attr['gyazourl']} #{attr['uploadurl']}]") if attr['gyazourl']
      obj['lines'] = lines
      pages.push(obj)
    }
    data['pages'] = pages

    puts data.to_json
    File.open("/Users/masui/Danshari/data#{@id}.json","w"){ |f|
      f.puts data.to_json
    }
    
  end
end

# puts ARGV.length
# exit

if ARGV.length == 0
  STDERR.puts "% danshari files"
  exit
end

d = Danshari.new(ARGV)
d.exec

