from setuptools import setup, find_packages

setup(
    name = 'munkipkg', 
    version='1.0',
    entry_points={'console_scripts': ['munkipkg = munkipkg:main']},
    packages=['']  
)
