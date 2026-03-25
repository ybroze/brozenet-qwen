FROM vllm/vllm-openai:nightly

COPY run_vllm.py /run_vllm.py

EXPOSE 8080

ENTRYPOINT ["python3", "/run_vllm.py"]

# CMD args are injected by Ansible / Cloud Build
