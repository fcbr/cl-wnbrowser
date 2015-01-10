(in-package :cl-wnbrowser)

(defun make-solr-query-uri ()
   (format nil "~a/~a/select"
	   *solr-endpoint-uri*
	   *solr-collection-id*))

(defun get-facets-for-solr-query ()
  (mapcar (lambda (f)
	    (cons "facet.field" (string f)))
	  *facets*))

(defun get-solr-query-plist (term df fq start rows)
  (append
   (list (when start (cons "start" start))
	 (when rows (cons "rows" rows))
	 (cons "q" term)
	 (when df (cons "df" df))
	 (when fq (cons "fq" fq))
	 (cons "wt" "json")
	 (cons "facet" "true")
	 (cons "facet.mincount" "1")
	 (cons "indent" "false"))
   (get-facets-for-solr-query)))

(defun execute-solr-query (term &optional &key df fq start rows)
  "Calls the SELECT web service at the predefined SOLR URI, 
with TERM as the search term and DF as the default field."
  (let ((stream (nth-value 0 (drakma:http-request
		 (make-solr-query-uri)
		 :method :post
		 :external-format-out :utf-8
		 :parameters (get-solr-query-plist term df fq start rows)
		 :want-stream t))))
    (setf (flexi-streams:flexi-stream-external-format stream) :utf-8)
    (let ((obj (yason:parse stream
			    :object-as :plist
			    :object-key-fn #'make-keyword)))
      (close stream)
      obj)))

(defun search-solr-internal (term fq start rows)
  (execute-solr-query term :df "text" :fq fq :start start :rows rows))

(defun search-solr-word-br (term start rows)
  (execute-solr-query (format nil "word_br:~a" term) :start start :rows rows))

(defun search-solr-by-id-internal (id)
  (execute-solr-query (format nil "\"~a\"" id) :df "id"))

(defun get-response (solr-result)
  (getf solr-result :|response|))

(defun get-docs (response)
  (getf response :|docs|))

(defun get-facet-fields (response)
  (getf (getf response :|facet_counts|) :|facet_fields|))

(defun get-facet-count (facet response)
  (let ((facets (getf (get-facet-fields response) facet)))
    (when facets
      (process-pairs #'(lambda (a b)
			 (list :|name| a :|count| b)) facets))))

(defun get-facets-count (response)
  (mapcar #'(lambda (facet-field)
	    (let ((facet (get-facet-count facet-field response)))
	      (cons facet-field facet)))
	  *facets*))

(defun get-num-found (response)
  (getf response :|numFound|))

(defun search-solr (term &optional fq start rows)
  (let* ((result (search-solr-internal term fq start rows))
	 (response (get-response result)))
    (values
     (get-num-found response)
     (get-docs response)
     (get-facets-count result))))

(defun search-solr-by-id (id)
  (let ((response (get-response (search-solr-by-id-internal id))))
    (car (get-docs response))))

(defun get-related-synsets (term)
  (let ((response (get-response (search-solr-word-br term "0" "1000"))))
    (get-docs response)))

(defun is-synset (doc)
  (= 0 (count "Nominalization" doc :test #'string-equal)))

(defun get-synset-word-en (synset-id)
  "Returns the FIRST entry in the word_en property for the given SYNSET-ID"
  (let* ((response (get-response (search-solr-by-id-internal synset-id)))
	 (symset-response (car (get-docs response))))
    (car (getf symset-response :|word_en|))))
