module Docsplit

=begin
This version of docsplit is modified to support our needs exactly as it fits our requirements.
  In case of requirement changes you have to modify some of the "hard coded variables" to support the new requirements.
  1. The MEMORY_ARGS constant is now hard coded, if you want to specify the memory limits that Graphicsmagick should use you have to:
    a. Change the limit in the result and cmd variables or,
    b. Let the user specify the memory limit by defining it as an instance variable in the extract_options method (not recommended).
  2. The quality is now hard coded to be 75 for both jpg and png formats we found this to be optimal for the image quality and size specially for png images.
  3. The density aka DPI is now hard coded to be 96 which fits best in our case if you want to modify it you have to do:
    a. Change the density in the result and cmd variables or,
    b. Let the user specify the density by defining it as an instance variable in the extract_options method which allow the user to pass it as a param.
  4. compress_images method is used to compress png images only. 
  5. For multithreading you can change the number of Cpus Graphicsmagick should use by modifing the OMP_NUM_THREADS
=end

  # Delegates to GraphicsMagick in order to convert PDF documents into
  # nicely sized images.
  class ImageExtractor

    # Extract a list of PDFs as rasterized page images, according to the
    # configuration in options.
    def extract(pdfs, options)
      puts pdfs, options.inspect
      @pdfs = [pdfs].flatten
      extract_options(options)
      @pdfs.each do |pdf|
        previous = nil
        @sizes.each_with_index do |size, i|
          @formats.each {|format| convert(pdf, size, format, previous) }
          previous = size if @rolling
        end
      end
    end

    def compress_images(directory)
      `for file in #{directory}/*.png; do pngnq -f "$file" && rm -rf "${file%.png}" && mv "${file%.png}-nq8.png" "$file";done`
    end
    def compress_1024x_images(directory)
      `for file in #{directory}/*.png; do pngnq -f "$file" && rm -rf "${file%.png}" && mv "${file%.png}-nq8.png" "$file";done`
    end
    # Convert a single PDF into page images at the specified size and format.
    # If `--rolling`, and we have a previous image at a larger size to work with,
    # we simply downsample that image, instead of re-rendering the entire PDF.
    # Now we generate one page at a time, a counterintuitive opimization
    # suggested by the GraphicsMagick list, that seems to work quite well.
    def convert(pdf, size, format, previous=nil)
      tempdir   = Dir.mktmpdir
      #basename  = File.basename(pdf, File.extname(pdf))
      directory = directory_for(size)
      pages     = @pages || '1-' + Docsplit.extract_length(pdf).to_s
      escaped_pdf = ESCAPE[pdf]
      FileUtils.mkdir_p(directory) unless File.exists?(directory)
      if previous
        FileUtils.cp(Dir[directory_for(previous) + '/*'], directory)
        result = `MAGICK_TMPDIR=#{tempdir} OMP_NUM_THREADS=4 gm mogrify -limit memory 1024MiB -limit map 512MiB -density #{@density} #{resize_arg(size)} -quality 100 \"#{directory}/*.#{format}\" 2>&1`.chomp
        raise ExtractionFailed, result if $? != 0
      else
        page_list(pages).each do |page|
          out_file  = ESCAPE[File.join(directory, "#{page}.#{format}")]
          cmd = "MAGICK_TMPDIR=#{tempdir} OMP_NUM_THREADS=4 gm convert +adjoin -define pdf:use-cropbox=true -limit memory 1024MiB -limit map 512MiB -density #{@density} #{resize_arg(size)} -quality 100 #{escaped_pdf}[#{page - 1}] #{out_file} 2>&1".chomp
          result = `#{cmd}`.chomp
          raise ExtractionFailed, result if $? != 0
        end
      end
    ensure
      FileUtils.remove_entry_secure tempdir if File.exists?(tempdir)
    end

    private

    # Extract the relevant GraphicsMagick options from the options hash.
    def extract_options(options)
      @output  = options[:output]  || '.'
      @pages   = options[:pages]
      @density = options[:density]
      @formats = [options[:format] || DEFAULT_FORMAT].flatten
      @sizes   = [options[:size]].flatten.compact
      @sizes   = [nil] if @sizes.empty?
    end

    # If there's only one size requested, generate the images directly into
    # the output directory. Multiple sizes each get a directory of their own.
    def directory_for(size)
      path = File.join(@output, size)
      File.expand_path(path)
    end

    # Generate the resize argument.
    def resize_arg(size)
      size.nil? ? '' : "-resize #{size}"
    end

    # Generate the expanded list of requested page numbers.
    def page_list(pages)
      pages.split(',').map { |range|
        if range.include?('-')
          range = range.split('-')
          Range.new(range.first.to_i, range.last.to_i).to_a.map {|n| n.to_i }
        else
          range.to_i
        end
      }.flatten.uniq.sort
    end

  end

end
